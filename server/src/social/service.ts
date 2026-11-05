// Duels, daily quests and the points wallet. All rules live here, on the server; the app only renders what this returns.
//
// Design choices worth knowing:
//  - Points are minted by the system when a duel is approved or a quest is claimed. Players NEVER stake or transfer points,
//    so nothing here is a wager (important before points could ever be cashed out; see docs/points-and-rewards.md).
//  - Every award has a unique ledger key, so it can be granted exactly once, even if a request is retried.
//  - Two accounts approving each other's duels is the obvious way to farm points, so rewards are capped per user per day,
//    and only the first approved duel between the same two people each day pays out.
import { randomUUID } from 'node:crypto';
import { checkPolicy, cleanText, FALLBACK_DRAFTS, CATEGORIES, withAudience } from '../policy/index.ts';
import { bandOf, sameBand } from '../profile/age.ts';
import type { Category, ChallengeDraft, Difficulty } from '../policy/index.ts';
import type { Duel, DuelStatus, LedgerEntry, Profile, Repo } from '../store/types.ts';
import { OPEN_DUEL } from '../store/types.ts';

export class SocialError extends Error {
  status: number; code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}

export const RULES = {
  maxOpenOutgoing: 5,
  ttlMs: { pending: 48 * 3_600_000, accepted: 72 * 3_600_000, submitted: 48 * 3_600_000 },
  rewardBase: 10,
  rewardPerLevel: 10,
  challengerBonus: 5,
  dailyCapTarget: 150,
  dailyCapChallenger: 30,
};

export const duelReward = (difficulty: number) => RULES.rewardBase + RULES.rewardPerLevel * Math.max(1, Math.min(5, difficulty));

export interface QuestDef { id: string; title: string; desc: string; goal: number; reward: number }
export const QUESTS: readonly QuestDef[] = [
  { id: 'play_round', title: 'Take the stage', desc: 'Play one round in a live session', goal: 1, reward: 10 },
  { id: 'complete_dare', title: 'Dare accomplished', desc: 'Complete one dare', goal: 1, reward: 25 },
  { id: 'send_duel', title: 'Throw down', desc: 'Challenge someone to a duel', goal: 1, reward: 15 },
  { id: 'finish_duel', title: 'Duel finisher', desc: 'Complete a duel someone sent you', goal: 1, reward: 30 },
];

const DAY_MS = 86_400_000;
export const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);
export const startOfUtcDay = (ms: number) => Date.parse(`${utcDay(ms)}T00:00:00.000Z`);

/** Consecutive active days ending today (or yesterday, so the streak is not lost before you have played today). */
export function computeStreak(active: Set<string>, nowMs: number): number {
  let day = startOfUtcDay(nowMs);
  if (!active.has(utcDay(day))) day -= DAY_MS;
  let n = 0;
  while (active.has(utcDay(day))) { n++; day -= DAY_MS; }
  return n;
}

/** Monday to Sunday of the current (UTC) week, each flagged active or not. */
export function weekStrip(active: Set<string>, nowMs: number) {
  const today = startOfUtcDay(nowMs);
  const dow = (new Date(today).getUTCDay() + 6) % 7;   // Monday = 0
  return Array.from({ length: 7 }, (_, i) => {
    const t = today - (dow - i) * DAY_MS;
    return { day: utcDay(t), label: ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]!, active: active.has(utcDay(t)), today: i === dow, future: t > today };
  });
}

export interface DuelIdea { index: number; title: string; objective: string; category: string; difficulty: number; durationSeconds: number }

export interface CustomDare { title: unknown; objective: unknown; difficulty?: unknown; category?: unknown }
export interface CreateDuelInput { targetId?: string; targetHandle?: string; libraryIndex?: number; custom?: CustomDare }

const hasLink = (s: string) => /https?:|www\.|@/i.test(s);

export class SocialService {
  private repo: Repo;
  private now: () => number;
  private rng: () => number;
  private uid: () => string;
  constructor(o: { repo: Repo; now?: () => number; rng?: () => number; uid?: () => string }) {
    this.repo = o.repo; this.now = o.now ?? Date.now; this.rng = o.rng ?? Math.random; this.uid = o.uid ?? randomUUID;
  }

  // ---- ideas -------------------------------------------------------------------------------------------------------

  /** The target's boundaries as the game will apply them: their own, plus the teen floor when they are 16-17. */
  private effectiveBoundaries(target: Profile) {
    return withAudience(target.boundaries, bandOf(target) === 'teen' ? 'teen' : 'adult');
  }

  /** Library dares that pass the target's own boundaries, so nobody is ever sent something they have ruled out. */
  async ideas(targetId: string, n = 6, viewer?: Profile): Promise<DuelIdea[]> {
    const target = await this.repo.getProfile(targetId);
    // Someone of the other age band answers exactly like someone who does not exist.
    if (!target || (viewer && !sameBand(viewer, target))) throw new SocialError(404, 'not_found', 'Player not found');
    const bounds = this.effectiveBoundaries(target);
    const ok = FALLBACK_DRAFTS.map((d, index) => ({ d, index })).filter(({ d }) => checkPolicy(d, bounds).ok);
    for (let i = ok.length - 1; i > 0; i--) { const j = Math.floor(this.rng() * (i + 1)); [ok[i], ok[j]] = [ok[j]!, ok[i]!]; }
    return ok.slice(0, n).map(({ d, index }) => ({ index, title: d.title, objective: d.objective, category: d.category, difficulty: d.difficulty, durationSeconds: d.durationSeconds }));
  }

  // ---- duels -------------------------------------------------------------------------------------------------------

  private async sweep(userId: string): Promise<Duel[]> {
    const list = await this.repo.listDuels(userId, 60);
    const t = this.now();
    for (const d of list) {
      if ((OPEN_DUEL as readonly string[]).includes(d.status) && Date.parse(d.expiresAt) <= t) {
        d.status = 'expired'; d.resolvedAt = new Date(t).toISOString();
        await this.repo.saveDuel(d);
      }
    }
    return list;
  }

  async list(userId: string): Promise<Duel[]> { return this.sweep(userId); }

  async create(challenger: Profile, input: CreateDuelInput): Promise<Duel> {
    let target: Profile | null = null;
    if (input.targetId) target = await this.repo.getProfile(String(input.targetId).slice(0, 64));
    else if (input.targetHandle) {
      const hits = await this.repo.searchHandles(String(input.targetHandle).trim().toLowerCase(), 1, []);
      const hit = hits.find((h) => h.handle === String(input.targetHandle).trim().toLowerCase());
      target = hit ? await this.repo.getProfile(hit.id) : null;
    }
    if (!target || !target.handle || !(target.ageVerifiedAt || target.role !== 'user')) throw new SocialError(404, 'not_found', 'We could not find that player');
    // Teens and adults never reach each other, and the answer does not reveal that the player exists.
    if (!sameBand(challenger, target)) throw new SocialError(404, 'not_found', 'We could not find that player');
    if (target.id === challenger.id) throw new SocialError(400, 'bad_target', 'You cannot challenge yourself');
    if (target.suspendedUntil && new Date(target.suspendedUntil) > new Date(this.now())) throw new SocialError(404, 'not_found', 'We could not find that player');
    if (await this.repo.blockedEitherWay(challenger.id, target.id)) throw new SocialError(403, 'blocked', 'You cannot challenge this player');

    const mine = await this.sweep(challenger.id);
    const open = mine.filter((d) => (OPEN_DUEL as readonly string[]).includes(d.status));
    if (open.filter((d) => d.challengerId === challenger.id).length >= RULES.maxOpenOutgoing) throw new SocialError(409, 'too_many', `You can have ${RULES.maxOpenOutgoing} open duels at a time`);
    if (open.some((d) => (d.challengerId === challenger.id && d.targetId === target!.id) || (d.challengerId === target!.id && d.targetId === challenger.id)))
      throw new SocialError(409, 'already_open', 'You already have an open duel with this player');

    let draft: ChallengeDraft; let origin: Duel['origin'];
    if (input.libraryIndex !== undefined) {
      const d = FALLBACK_DRAFTS[Number(input.libraryIndex)];
      if (!d) throw new SocialError(400, 'bad_dare', 'Unknown dare');
      draft = d; origin = 'library';
    } else if (input.custom) {
      // Free text between two teens is the easiest place for pressure and bullying to start, so teens pick from the dare ideas.
      if (bandOf(target) === 'teen' || bandOf(challenger) === 'teen') throw new SocialError(400, 'bad_dare', 'Teen accounts can pick from the dare ideas, but cannot write their own');
      const title = cleanText(String(input.custom.title ?? '')).slice(0, 40);
      const objective = cleanText(String(input.custom.objective ?? '')).slice(0, 200);
      if (title.length < 3) throw new SocialError(400, 'bad_dare', 'Give the dare a short title (3 to 40 characters)');
      if (objective.length < 10) throw new SocialError(400, 'bad_dare', 'Describe the dare in at least 10 characters');
      if (hasLink(title) || hasLink(objective)) throw new SocialError(400, 'bad_dare', 'Dares cannot contain links or @handles');
      const difficulty = Math.max(1, Math.min(5, Math.round(Number(input.custom.difficulty) || 2))) as Difficulty;
      const category = (CATEGORIES as readonly string[]).includes(String(input.custom.category)) ? (String(input.custom.category) as Category) : 'perform';
      draft = { category, title, objective, durationSeconds: 60, difficulty, completionCriteria: ['The dare is done as described'], allowedModifiers: [], scoringType: 'audience_judgment', tags: [] };
      origin = 'custom';
    } else throw new SocialError(400, 'bad_dare', 'Pick a dare or write your own');

    // The same safety rules as the live game, checked against the TARGET's boundaries.
    const verdict = checkPolicy(draft, this.effectiveBoundaries(target));
    if (!verdict.ok) throw new SocialError(400, 'unsafe_dare', verdict.reasons.some((r) => r.startsWith('boundary:'))
      ? 'That dare goes against this player\'s boundaries. Try a different one.' : 'That dare is not allowed on DAREWIRE. Try a different one.');

    const t = this.now();
    const duel: Duel = {
      id: this.uid(),
      challengerId: challenger.id, challengerHandle: challenger.handle ?? '?', challengerAvatar: challenger.avatar,
      targetId: target.id, targetHandle: target.handle, targetAvatar: target.avatar,
      title: draft.title, objective: draft.objective, category: draft.category, difficulty: draft.difficulty, durationSeconds: draft.durationSeconds,
      criteria: draft.completionCriteria, origin, status: 'pending', note: '', proofClipId: null,
      reward: duelReward(draft.difficulty), rewarded: 0,
      createdAt: new Date(t).toISOString(), updatedAt: new Date(t).toISOString(), expiresAt: new Date(t + RULES.ttlMs.pending).toISOString(), resolvedAt: null,
    };
    return this.repo.createDuel(duel);
  }

  private async load(userId: string, id: string): Promise<Duel> {
    const d = await this.repo.getDuel(id);
    if (!d || (d.challengerId !== userId && d.targetId !== userId)) throw new SocialError(404, 'not_found', 'Duel not found');
    if ((OPEN_DUEL as readonly string[]).includes(d.status) && Date.parse(d.expiresAt) <= this.now()) {
      d.status = 'expired'; d.resolvedAt = new Date(this.now()).toISOString(); await this.repo.saveDuel(d);
      throw new SocialError(409, 'expired', 'This duel has expired');
    }
    return d;
  }

  private async move(d: Duel, to: DuelStatus, ttl?: number): Promise<Duel> {
    const t = this.now();
    d.status = to;
    if (ttl) d.expiresAt = new Date(t + ttl).toISOString();
    if (!(OPEN_DUEL as readonly string[]).includes(to)) d.resolvedAt = new Date(t).toISOString();
    await this.repo.saveDuel(d);
    return d;
  }

  async respond(userId: string, id: string, action: 'accept' | 'decline' | 'cancel'): Promise<Duel> {
    const d = await this.load(userId, id);
    if (action === 'cancel') {
      if (d.challengerId !== userId) throw new SocialError(403, 'forbidden', 'Only the challenger can cancel');
      if (d.status !== 'pending' && d.status !== 'accepted') throw new SocialError(409, 'bad_state', 'This duel can no longer be cancelled');
      return this.move(d, 'cancelled');
    }
    if (d.targetId !== userId) throw new SocialError(403, 'forbidden', 'Only the challenged player can answer');
    if (d.status !== 'pending') throw new SocialError(409, 'bad_state', 'This duel was already answered');
    return action === 'accept' ? this.move(d, 'accepted', RULES.ttlMs.accepted) : this.move(d, 'declined');
  }

  async submit(userId: string, id: string, input: { note?: unknown; clipId?: unknown }): Promise<Duel> {
    const d = await this.load(userId, id);
    if (d.targetId !== userId) throw new SocialError(403, 'forbidden', 'Only the challenged player can submit');
    if (d.status !== 'accepted') throw new SocialError(409, 'bad_state', 'Accept the duel first');
    const note = cleanText(String(input.note ?? '')).slice(0, 200);
    if (hasLink(note)) throw new SocialError(400, 'bad_note', 'Notes cannot contain links or @handles');
    let proof: string | null = null;
    if (input.clipId) {
      const clip = await this.repo.getClip(String(input.clipId));
      if (!clip || clip.authorId !== userId || clip.status !== 'published') throw new SocialError(400, 'bad_clip', 'Pick one of your own posted dare videos');
      proof = clip.id;
    }
    d.note = note; d.proofClipId = proof;
    return this.move(d, 'submitted', RULES.ttlMs.submitted);
  }

  /** The challenger decides. Approval pays the target (and gives the challenger a small bonus), subject to daily caps. */
  async judge(userId: string, id: string, approve: boolean): Promise<{ duel: Duel; paid: number; capped: boolean }> {
    const d = await this.load(userId, id);
    if (d.challengerId !== userId) throw new SocialError(403, 'forbidden', 'Only the challenger can judge');
    if (d.status !== 'submitted') throw new SocialError(409, 'bad_state', 'There is nothing to judge yet');
    if (!approve) return { duel: await this.move(d, 'rejected'), paid: 0, capped: false };

    const t = this.now();
    const dayStart = new Date(startOfUtcDay(t)).toISOString();
    const pairDuels = (await this.repo.listDuels(d.targetId, 100)).filter((x) =>
      x.id !== d.id && x.status === 'completed' && x.rewarded > 0 && (x.resolvedAt ?? '') >= dayStart &&
      ((x.challengerId === d.challengerId && x.targetId === d.targetId) || (x.challengerId === d.targetId && x.targetId === d.challengerId)));
    let reward = d.reward; let capped = false;
    if (pairDuels.length > 0) { reward = 0; capped = true; }
    else {
      const earned = await this.repo.ledgerSince(d.targetId, ['duel_win'], dayStart);
      const room = Math.max(0, RULES.dailyCapTarget - earned);
      if (reward > room) { reward = room; capped = true; }
    }
    let paid = 0;
    if (reward > 0) {
      const e = await this.repo.addPoints({ userId: d.targetId, amount: reward, kind: 'duel_win', ref: d.id, key: `duel:${d.id}:target`, note: `Completed "${d.title}"` });
      if (e) paid = e.amount;
    }
    if (paid > 0) {
      const earnedC = await this.repo.ledgerSince(d.challengerId, ['duel_bonus'], dayStart);
      const bonus = Math.min(RULES.challengerBonus, Math.max(0, RULES.dailyCapChallenger - earnedC));
      if (bonus > 0) await this.repo.addPoints({ userId: d.challengerId, amount: bonus, kind: 'duel_bonus', ref: d.id, key: `duel:${d.id}:challenger`, note: `Your duel "${d.title}" was completed` });
    }
    d.rewarded = paid;
    return { duel: await this.move(d, 'completed'), paid, capped };
  }

  // ---- wallet and quests -------------------------------------------------------------------------------------------

  async wallet(userId: string) {
    const stats = await this.repo.userStats(userId);
    const [ledger, rounds] = await Promise.all([this.repo.ledger(userId, 40), this.repo.history(userId, 40)]);
    const activity = [
      ...ledger.map((e: LedgerEntry) => ({ id: e.id, amount: e.amount, kind: e.kind as string, note: e.note, at: Date.parse(e.createdAt) })),
      ...rounds.filter((r) => r.playerPoints > 0).map((r) => ({ id: `r${r.round}-${r.at}`, amount: r.playerPoints, kind: 'round', note: r.challengeTitle ? `Round: ${r.challengeTitle}` : 'Round played', at: r.at })),
    ].sort((a, b) => b.at - a.at).slice(0, 40);
    return {
      balance: stats.points,
      completed: stats.completed,
      activity,
      // Honest status: there is no cash-out. Points are not money and nothing here promises that they will become money.
      cashOut: { available: false, note: 'Cash-out is not available. Points are for status and rewards inside DAREWIRE for now.' },
    };
  }

  private async activeDays(userId: string): Promise<Set<string>> {
    const days = new Set<string>();
    for (const r of await this.repo.history(userId, 50)) if (r.outcome === 'completed') days.add(utcDay(r.at));
    for (const d of await this.sweep(userId)) if (d.targetId === userId && d.status === 'completed' && d.resolvedAt) days.add(d.resolvedAt.slice(0, 10));
    return days;
  }

  async quests(userId: string) {
    const t = this.now();
    const day = utcDay(t); const dayStartMs = startOfUtcDay(t);
    const [rounds, duels, ledger, active] = await Promise.all([this.repo.history(userId, 50), this.sweep(userId), this.repo.ledger(userId, 100), this.activeDays(userId)]);
    const progress: Record<string, number> = {
      play_round: rounds.filter((r) => r.at >= dayStartMs).length,
      complete_dare: rounds.filter((r) => r.at >= dayStartMs && r.outcome === 'completed').length,
      send_duel: duels.filter((d) => d.challengerId === userId && Date.parse(d.createdAt) >= dayStartMs).length,
      finish_duel: duels.filter((d) => d.targetId === userId && d.status === 'completed' && (d.resolvedAt ?? '') >= new Date(dayStartMs).toISOString()).length,
    };
    const claimedKeys = new Set(ledger.map((e) => e.key));
    return {
      day,
      streak: computeStreak(active, t),
      week: weekStrip(active, t),
      quests: QUESTS.map((q) => ({ ...q, progress: Math.min(q.goal, progress[q.id] ?? 0), claimed: claimedKeys.has(`quest:${q.id}:${day}:${userId}`) })),
    };
  }

  async claim(userId: string, questId: string): Promise<{ amount: number }> {
    const def = QUESTS.find((q) => q.id === questId);
    if (!def) throw new SocialError(404, 'not_found', 'Unknown quest');
    const state = (await this.quests(userId)).quests.find((q) => q.id === questId)!;
    if (state.claimed) throw new SocialError(409, 'claimed', 'You already claimed this today');
    if (state.progress < def.goal) throw new SocialError(409, 'not_done', 'Finish the quest first');
    const e = await this.repo.addPoints({ userId, amount: def.reward, kind: 'quest', ref: def.id, key: `quest:${def.id}:${utcDay(this.now())}:${userId}`, note: def.title });
    if (!e) throw new SocialError(409, 'claimed', 'You already claimed this today');
    return { amount: e.amount };
  }
}

/** What a client may see of a duel, from one participant's point of view. */
export function duelView(d: Duel, viewerId: string) {
  const mineAsChallenger = d.challengerId === viewerId;
  return {
    id: d.id, role: mineAsChallenger ? 'challenger' : 'target',
    other: mineAsChallenger ? { id: d.targetId, handle: d.targetHandle, avatar: d.targetAvatar } : { id: d.challengerId, handle: d.challengerHandle, avatar: d.challengerAvatar },
    title: d.title, objective: d.objective, category: d.category, difficulty: d.difficulty, durationSeconds: d.durationSeconds, criteria: d.criteria,
    status: d.status, note: d.note, proofClipId: d.proofClipId, reward: d.reward, rewarded: d.rewarded, origin: d.origin,
    createdAt: d.createdAt, expiresAt: d.expiresAt, resolvedAt: d.resolvedAt,
  };
}
