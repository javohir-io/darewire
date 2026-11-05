// Clip recorder. Turns a finished round into a clip the Player can choose to post. Consent rules, enforced here:
//  * Recording only starts if the Player ticked "allow clips" for this run, and only after they ACCEPT a dare.
//  * Safety Stop, a moderator cut, abandonment or session end => recording stopped and the file is DELETED. Never offered.
//  * Only completed or failed rounds are offered. Nothing is public until the Player publishes it (POST /v1/clips/:id/publish).
//  * Unpublished clips expire after 24 hours (see SessionManager sweep).
import { randomUUID } from 'node:crypto';
import type { EngineEvent } from '../engine/index.ts';
import type { Egress } from '../media/egress.ts';
import type { Storage } from '../media/storage.ts';
import type { Clip, Repo } from '../store/types.ts';
import { log } from '../util/log.ts';

export interface RecCtx {
  sessionId: string;
  phase: string;
  allowClips: boolean;
  player: { id: string; handle: string; avatar: string } | null;
  round: { n: number; title: string; category: string; difficulty: number; twist: string | null } | null;
}

interface Rec {
  key: string; sessionId: string; round: number; filepath: string; startedAt: number; stoppedAt: number | null;
  egressId: string | null; startFailed: boolean; start: Promise<void>;
  fileOk: boolean | null; outcome: string | null; settled: boolean;
  author: { id: string; handle: string; avatar: string }; title: string; category: string; difficulty: number; twist: string | null;
}

export interface RecorderDeps {
  repo: Repo;
  egress: Egress;
  storage: Storage | null;
  onReady: (sessionId: string, userId: string, clip: Clip) => void;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  maxPolls?: number;
  pollMs?: number;
}

const OFFERABLE = new Set(['completed', 'failed']);
const DISCARD_EVENTS = new Set(['safety:stop', 'stream:cut', 'session:ended']);

export class Recorder {
  private d: Required<Omit<RecorderDeps, 'storage'>> & { storage: Storage | null };
  private recs = new Map<string, Rec>();

  constructor(deps: RecorderDeps) {
    this.d = { now: Date.now, sleep: (ms) => new Promise((r) => setTimeout(r, ms)), maxPolls: 40, pollMs: 3000, ...deps };
  }

  active(): number { return this.recs.size; }

  /** Called by the manager after every batch of engine events. Never throws. */
  handle(ctx: RecCtx, events: EngineEvent[]): void {
    for (const e of events) {
      try { this.one(ctx, e); } catch (err) { log('warn', 'recorder error', { err: err instanceof Error ? err.message : 'unknown' }); }
    }
  }

  private current(sessionId: string, round?: number): Rec | undefined {
    for (const r of this.recs.values()) if (r.sessionId === sessionId && !r.settled && (round === undefined || r.round === round) && r.outcome === null) return r;
    return undefined;
  }

  private one(ctx: RecCtx, e: EngineEvent): void {
    if (e.type === 'accepted' && ctx.allowClips && ctx.player && ctx.round && !this.current(ctx.sessionId, ctx.round.n)) {
      this.begin(ctx);
      return;
    }
    const rec = this.current(ctx.sessionId);
    if (!rec) return;
    if (DISCARD_EVENTS.has(e.type)) { rec.outcome = 'discard'; this.stop(rec); this.settle(rec); return; }
    if (e.type === 'round:result') {
      rec.outcome = String(e.data.outcome ?? 'discard');
      if (ctx.round?.twist) rec.twist = ctx.round.twist;
      if (rec.stoppedAt === null) this.stop(rec);
      this.settle(rec);
      return;
    }
    if (e.type === 'phase' && ctx.phase !== 'LIVE_ROUND' && rec.stoppedAt === null) this.stop(rec);
  }

  private begin(ctx: RecCtx): void {
    const id = randomUUID();
    const rec: Rec = {
      key: id, sessionId: ctx.sessionId, round: ctx.round!.n, filepath: `clips/${ctx.sessionId}/${ctx.round!.n}-${id}.mp4`,
      startedAt: this.d.now(), stoppedAt: null, egressId: null, startFailed: false, start: Promise.resolve(),
      fileOk: null, outcome: null, settled: false, author: ctx.player!, title: ctx.round!.title, category: ctx.round!.category,
      difficulty: ctx.round!.difficulty, twist: ctx.round!.twist,
    };
    rec.start = this.d.egress.start(ctx.sessionId, rec.filepath).then((eid) => { rec.egressId = eid; }).catch((err) => {
      rec.startFailed = true; log('warn', 'egress start failed', { err: err instanceof Error ? err.message : 'unknown' });
    });
    this.recs.set(rec.key, rec);
  }

  private stop(rec: Rec): void {
    if (rec.stoppedAt !== null) return;
    rec.stoppedAt = this.d.now();
    void this.finish(rec);
  }

  private async finish(rec: Rec): Promise<void> {
    await rec.start;
    if (rec.startFailed || !rec.egressId) { rec.fileOk = false; this.settle(rec); return; }
    try { await this.d.egress.stop(rec.egressId); } catch { /* already ending */ }
    let ok = false;
    for (let i = 0; i < this.d.maxPolls; i++) {
      let st: 'active' | 'complete' | 'failed' = 'active';
      try { st = await this.d.egress.status(rec.egressId); } catch { /* transient */ }
      if (st === 'complete') { ok = true; break; }
      if (st === 'failed') break;
      await this.d.sleep(this.d.pollMs);
    }
    rec.fileOk = ok;
    this.settle(rec);
  }

  /** Decide once both facts are known: is the file ready, and how did the round end? */
  private settle(rec: Rec): void {
    if (rec.settled || rec.fileOk === null || rec.outcome === null) return;
    rec.settled = true;
    void (async () => {
      try {
        if (!rec.fileOk) return;
        if (!OFFERABLE.has(rec.outcome!)) { await this.d.storage?.remove(rec.filepath); return; }   // consent rule: never keep it
        const clip = await this.d.repo.createClip({
          sessionId: rec.sessionId, roundNo: rec.round, authorId: rec.author.id, authorHandle: rec.author.handle, authorAvatar: rec.author.avatar,
          title: rec.title, category: rec.category, difficulty: rec.difficulty, twist: rec.twist,
          durationMs: Math.max(0, (rec.stoppedAt ?? this.d.now()) - rec.startedAt), storagePath: rec.filepath,
        });
        this.d.onReady(rec.sessionId, rec.author.id, clip);
      } catch (err) {
        log('error', 'clip settle failed', { err: err instanceof Error ? err.message : 'unknown' });
      } finally {
        this.recs.delete(rec.key);
      }
    })();
  }
}
