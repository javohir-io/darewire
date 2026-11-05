// The AI Director proposes challenges. It never owns game state and its output is untrusted input:
//   parse (schema) -> deterministic policy -> de-duplicate -> optional independent model review -> select five -> fill with fallbacks.
// Nothing reaches the engine unless it passed every step; if the model is down or misbehaves, approved fallbacks are used.
import { parseCandidate } from '../policy/parse.ts';
import { checkPolicy, similarity } from '../policy/policy.ts';
import { FALLBACK_DRAFTS } from '../policy/fallbacks.ts';
import {
  CATEGORIES, CHALLENGE_SCHEMA_VERSION, type Boundaries, type Category, type Challenge, type ChallengeDraft, type Difficulty,
} from '../policy/types.ts';
import type { LlmClient } from './llm.ts';
import { CHALLENGE_SCHEMA, DIRECTOR_SYSTEM, REVIEW_SCHEMA, REVIEW_SYSTEM, generationPrompt, reviewPrompt } from './prompt.ts';

export interface GenerationContext { difficulty: Difficulty; boundaries: Boundaries; recentTitles: string[]; forceFallback?: boolean }

export interface Rejection { title: string; reasons: string[] }
export interface GenerationReport {
  requested: number; parsed: number; aiAccepted: number; fallbackUsed: number; attempts: number;
  rejected: Rejection[]; reviewer: 'off' | 'ok' | 'failed'; error: string | null; ms: number;
}
export interface GenerationResult { options: Challenge[]; report: GenerationReport }

export interface DirectorDeps {
  llm: LlmClient | null;
  review: boolean;
  rng: () => number;
  uid: () => string;
  now?: () => number;
  maxAttempts?: number;
  requestCount?: number;
  timeoutMs?: number;
  onReport?: (r: GenerationReport) => void;
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

export class Director {
  private d: Required<Omit<DirectorDeps, 'llm' | 'onReport'>> & Pick<DirectorDeps, 'llm' | 'onReport'>;

  constructor(deps: DirectorDeps) {
    this.d = { now: Date.now, maxAttempts: 2, requestCount: 8, timeoutMs: 12_000, ...deps };
  }

  async generate(ctx: GenerationContext): Promise<GenerationResult> {
    const t0 = this.d.now();
    const report: GenerationReport = { requested: 0, parsed: 0, aiAccepted: 0, fallbackUsed: 0, attempts: 0, rejected: [], reviewer: 'off', error: null, ms: 0 };
    const accepted: ChallengeDraft[] = [];
    const recent = new Set(ctx.recentTitles.map(norm));

    if (this.d.llm && !ctx.forceFallback) {
      for (let a = 0; a < this.d.maxAttempts && accepted.length < 5; a++) {
        report.attempts++;
        let raw: unknown;
        try {
          raw = await this.d.llm.json({
            system: DIRECTOR_SYSTEM, prompt: generationPrompt(this.d.requestCount, ctx.difficulty, ctx.boundaries, ctx.recentTitles),
            schema: CHALLENGE_SCHEMA, timeoutMs: this.d.timeoutMs,
          });
        } catch (e) {
          report.error = e instanceof Error ? e.message.slice(0, 80) : 'llm_error';
          continue;
        }
        const items = (raw && typeof raw === 'object' && Array.isArray((raw as { challenges?: unknown }).challenges)) ? (raw as { challenges: unknown[] }).challenges.slice(0, 12) : [];
        report.requested += this.d.requestCount;
        const fresh: ChallengeDraft[] = [];
        for (const item of items) {
          const p = parseCandidate(item);
          const title = typeof (item as { title?: unknown })?.title === 'string' ? String((item as { title: string }).title).slice(0, 48) : '?';
          if (!p.ok) { report.rejected.push({ title, reasons: p.errors.slice(0, 3) }); continue; }
          report.parsed++;
          const pol = checkPolicy(p.value, ctx.boundaries);
          if (!pol.ok) { report.rejected.push({ title, reasons: pol.reasons }); continue; }
          if (recent.has(norm(p.value.title))) { report.rejected.push({ title, reasons: ['recently_played'] }); continue; }
          if ([...accepted, ...fresh].some((x) => similarity(x, p.value) > 0.6)) { report.rejected.push({ title, reasons: ['near_duplicate'] }); continue; }
          fresh.push(p.value);
        }
        const approved = await this.review(fresh, report);
        accepted.push(...approved);
      }
    }

    report.aiAccepted = accepted.length;
    const chosen = this.selectFive(accepted, ctx);
    const aiCount = chosen.length;
    this.fillFromFallbacks(chosen, ctx);
    report.fallbackUsed = Math.max(0, chosen.length - aiCount);

    const options: Challenge[] = chosen.map((c, i) => ({ ...c, id: this.d.uid(), origin: i < aiCount ? 'ai' : 'fallback', schemaVersion: CHALLENGE_SCHEMA_VERSION }));
    report.ms = this.d.now() - t0;
    this.d.onReport?.(report);
    return { options, report };
  }

  /** Independent model review. Fails CLOSED: if the reviewer is enabled and unavailable, no AI candidate is used. */
  private async review(cands: ChallengeDraft[], report: GenerationReport): Promise<ChallengeDraft[]> {
    if (!this.d.review || !this.d.llm) return cands;
    if (!cands.length) return cands;
    try {
      const raw = await this.d.llm.json({ system: REVIEW_SYSTEM, prompt: reviewPrompt(cands), schema: REVIEW_SCHEMA, timeoutMs: this.d.timeoutMs, temperature: 0 });
      const verdicts = (raw as { verdicts?: unknown })?.verdicts;
      if (!Array.isArray(verdicts)) throw new Error('review_malformed');
      const ok = new Set<number>();
      for (const v of verdicts) {
        const x = v as { index?: unknown; approved?: unknown };
        if (typeof x.index === 'number' && Number.isInteger(x.index) && x.approved === true) ok.add(x.index);
      }
      report.reviewer = 'ok';
      const out: ChallengeDraft[] = [];
      cands.forEach((c, i) => { if (ok.has(i)) out.push(c); else report.rejected.push({ title: c.title, reasons: ['reviewer_rejected'] }); });
      return out;
    } catch (e) {
      report.reviewer = 'failed';
      report.error = e instanceof Error ? e.message.slice(0, 80) : 'review_error';
      for (const c of cands) report.rejected.push({ title: c.title, reasons: ['reviewer_unavailable'] });
      return [];
    }
  }

  /** Up to five candidates, spread across categories (at most two of one category). */
  private selectFive(pool: ChallengeDraft[], ctx: GenerationContext): ChallengeDraft[] {
    const out: ChallengeDraft[] = [];
    const count = (c: Category) => out.filter((o) => o.category === c).length;
    const left = [...pool];
    for (const cap of [2, 5]) {
      while (out.length < 5) {
        const cands = left.filter((c) => count(c.category) < cap);
        if (!cands.length) break;
        cands.sort((a, b) => count(a.category) - count(b.category) || Math.abs(a.difficulty - ctx.difficulty) - Math.abs(b.difficulty - ctx.difficulty));
        const pick = cands[0]!;
        out.push(pick); left.splice(left.indexOf(pick), 1);
      }
    }
    return out;
  }

  private fillFromFallbacks(chosen: ChallengeDraft[], ctx: GenerationContext): void {
    const recent = new Set(ctx.recentTitles.map(norm));
    const legal = FALLBACK_DRAFTS.filter((f) => checkPolicy(f, ctx.boundaries).ok);
    const tiers: ((f: ChallengeDraft) => boolean)[] = [
      (f) => !recent.has(norm(f.title)) && !chosen.some((c) => norm(c.title) === norm(f.title) || similarity(c, f) > 0.6),
      (f) => !chosen.some((c) => norm(c.title) === norm(f.title)),
    ];
    for (const ok of tiers) {
      while (chosen.length < 5) {
        const cands = legal.filter(ok);
        if (!cands.length) break;
        const cnt = (c: Category) => chosen.filter((o) => o.category === c).length;
        cands.sort((a, b) => cnt(a.category) - cnt(b.category) || Math.abs(a.difficulty - ctx.difficulty) - Math.abs(b.difficulty - ctx.difficulty) || this.d.rng() - 0.5);
        chosen.push(cands[0]!);
      }
    }
    // Pathological boundaries (almost everything excluded): repeat what is left rather than publish nothing.
    for (let i = 0; chosen.length < 5 && legal.length > 0 && i < 20; i++) chosen.push(legal[i % legal.length]!);
  }
}

export { CATEGORIES };
