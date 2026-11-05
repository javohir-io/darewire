// DAREWIRE game engine: a deterministic, server-authoritative state machine for one session.
//
//   LOBBY -> READY_CHECK -> CHALLENGE_GENERATION -> CHALLENGE_VOTE -> PLAYER_REVIEW -> LIVE_ROUND
//         -> SUBMISSION -> AUDIENCE_VERDICT -> ROUND_RESULT -> (next round | LOBBY | SESSION_END)
//
// Design rules (see docs/game-rules.md):
//  * The clock, RNG and id generator are injected, so every behaviour is testable without real time.
//  * Clients are always `user` actors. Deadline expiry, publishing options and moderation are separate
//    entry points that a client message can never reach.
//  * Nothing here does I/O. Side effects (call the AI, cut a LiveKit stream) are returned as `Effect`s.
//  * Safety Stop and moderator actions take precedence over ordinary progression.
import { buildTwistOptions } from '../policy/modifiers.ts';
import { sanitizeBoundaries, withAudience, DEFAULT_BOUNDARIES, type Boundaries, type Challenge, type Difficulty } from '../policy/types.ts';
import {
  HISTORY_LIMIT, MIN_EARLY_LOCK_MS, NOTE_MAX, POINTS, RECENT_TITLES, DEFAULT_TIMINGS, pickWinner, playerPoints,
} from './rules.ts';
import type {
  Actor, EngineDeps, EngineEvent, EngineResult, EngineState, Effect, ErrorCode, Outcome, Participant,
  Phase, Role, Round, RoundResult, SessionConfig, Timings,
} from './types.ts';

const fail = (code: ErrorCode, message: string): { ok: false; code: ErrorCode; message: string } => ({ ok: false, code, message });
const ATTEMPT_PHASES: Phase[] = ['READY_CHECK', 'CHALLENGE_GENERATION', 'CHALLENGE_VOTE', 'PLAYER_REVIEW', 'LIVE_ROUND', 'SUBMISSION'];

export interface NewSessionInput {
  id: string; code: string; title: string; hostId: string;
  /** Who the session is for (the host's age band). Defaults to adult. */
  band?: 'teen' | 'adult';
  twist?: boolean; maxWatchers?: number; startDifficulty?: Difficulty; timings?: Partial<Timings>;
}

export class GameSession {
  s: EngineState;
  private deps: EngineDeps;
  private events: EngineEvent[] = [];
  private effects: Effect[] = [];

  constructor(state: EngineState, deps: EngineDeps) {
    this.s = state;
    this.deps = deps;
  }

  static create(input: NewSessionInput, deps: EngineDeps): GameSession {
    const now = deps.now();
    const config: SessionConfig = {
      title: input.title.slice(0, 60), hostId: input.hostId, band: input.band ?? 'adult', twist: input.twist ?? true,
      maxWatchers: input.maxWatchers ?? 500, startDifficulty: input.startDifficulty ?? 2,
      timings: { ...DEFAULT_TIMINGS, ...input.timings },
    };
    return new GameSession({
      id: input.id, code: input.code, config, phase: 'LOBBY', rev: 0, createdAt: now, phaseStartedAt: now, phaseDeadline: null,
      participants: {}, queue: [], banned: [], playerId: null, boundaries: withAudience(DEFAULT_BOUNDARIES, config.band),
      roundNumber: 0, completedCount: 0, recentTitles: [], round: null, history: [], playerGraceUntil: null,
      generation: { token: 0, attempts: 0 }, streamCut: false, endedReason: null,
    }, deps);
  }

  static restore(snapshot: EngineState, deps: EngineDeps): GameSession {
    return new GameSession(structuredClone(snapshot), deps);
  }

  snapshot(): EngineState { return structuredClone(this.s); }

  /** Events and effects produced since the last drain. The runtime broadcasts events and executes effects. */
  drain(): { events: EngineEvent[]; effects: Effect[] } {
    const out = { events: this.events, effects: this.effects };
    this.events = []; this.effects = [];
    return out;
  }

  // ---- internals -------------------------------------------------------------------------------------------

  private get t(): Timings { return this.s.config.timings; }
  private emit(type: string, data: Record<string, unknown> = {}): void { this.s.rev++; this.events.push({ rev: this.s.rev, type, data }); }
  private isUser(a: Actor): a is Extract<Actor, { kind: 'user' }> { return a.kind === 'user'; }
  private isPlayer(a: Actor): boolean { return this.isUser(a) && a.id === this.s.playerId; }
  private isHostOrPlayer(a: Actor): boolean { return this.isUser(a) && (a.id === this.s.config.hostId || a.id === this.s.playerId); }
  private who(a: Actor): Participant | undefined { return this.isUser(a) ? this.s.participants[a.id] : undefined; }

  private setPhase(p: Phase, deadline: number | null): void {
    const now = this.deps.now();
    this.s.phase = p; this.s.phaseStartedAt = now; this.s.phaseDeadline = deadline;
    this.emit('phase', { phase: p });
  }

  private award(userId: string, pts: number): void {
    const r = this.s.round; const p = this.s.participants[userId];
    if (!r || pts <= 0) return;
    r.awards[userId] = (r.awards[userId] ?? 0) + pts;
    if (p) p.score += pts;
  }

  private newRound(): Round {
    this.s.roundNumber++;
    return {
      n: this.s.roundNumber, options: [], votes: {}, voteAt: {}, voteAwarded: {}, chosenIdx: null, chosenBy: null, finalTally: null,
      passes: 0, startedAt: null, deadline: null, endedAt: null, twist: null, note: null, verdicts: {}, verdictClosed: false, awards: {}, result: null,
    };
  }

  private targetDifficulty(): Difficulty {
    const d = this.s.config.startDifficulty + Math.floor(this.s.completedCount / 2);
    return Math.max(1, Math.min(this.s.boundaries.maxDifficulty, 5, d)) as Difficulty;
  }

  private beginGeneration(fresh: boolean): void {
    const now = this.deps.now();
    if (fresh || !this.s.round) this.s.round = this.newRound();
    const r = this.s.round;
    r.options = []; r.votes = {}; r.voteAt = {}; r.chosenIdx = null; r.chosenBy = null; r.finalTally = null;
    this.s.generation = { token: this.s.generation.token + 1, attempts: 0 };
    this.setPhase('CHALLENGE_GENERATION', now + this.t.generationMs);
    this.effects.push({
      type: 'generate', token: this.s.generation.token, round: r.n, difficulty: this.targetDifficulty(),
      boundaries: structuredClone(this.s.boundaries), recentTitles: [...this.s.recentTitles], forceFallback: false,
    });
  }

  private invalidateGeneration(): void { this.s.generation = { token: this.s.generation.token + 1, attempts: 0 }; }

  private toLobby(reason: string, vacate = false): void {
    this.invalidateGeneration();
    this.s.round = null; this.s.playerGraceUntil = null;
    if (vacate) this.vacatePlayer();
    this.setPhase('LOBBY', null);
    this.emit('lobby', { reason });
  }

  private vacatePlayer(): void {
    const id = this.s.playerId;
    if (id && this.s.participants[id]) this.s.participants[id]!.role = 'watcher';
    this.s.playerId = null;
    this.s.boundaries = withAudience(DEFAULT_BOUNDARIES, this.s.config.band);
  }

  // ---- membership ------------------------------------------------------------------------------------------

  join(actor: Actor, profile: { handle: string; avatar: string }, want: Role = 'watcher'): EngineResult<{ role: Role }> {
    if (!this.isUser(actor)) return fail('forbidden', 'Only users can join');
    if (this.s.phase === 'SESSION_END') return fail('ended', 'This session has ended');
    if (this.s.banned.includes(actor.id)) return fail('banned', 'You cannot join this session');
    const existing = this.s.participants[actor.id];
    if (existing) {
      existing.online = true; existing.handle = profile.handle; existing.avatar = profile.avatar;
      if (actor.id === this.s.playerId) this.s.playerGraceUntil = null;
      this.emit('presence', { userId: actor.id, online: true });
      return { ok: true, role: existing.role };
    }
    const watchers = Object.values(this.s.participants).filter((p) => p.role === 'watcher').length;
    if (watchers >= this.s.config.maxWatchers) return fail('full', 'This session is full');
    const p: Participant = {
      id: actor.id, handle: profile.handle, avatar: profile.avatar, role: 'watcher', joinedAt: this.deps.now(), online: true,
      score: 0, streak: 0, roundsPlayed: 0, roundsCompleted: 0, votesCast: 0, calledIt: 0,
    };
    this.s.participants[actor.id] = p;
    if (want === 'player') {
      if (!this.s.playerId && this.s.phase === 'LOBBY') { p.role = 'player'; this.s.playerId = p.id; }
      else this.s.queue.push(p.id);
    }
    this.emit('joined', { userId: p.id, role: p.role });
    return { ok: true, role: p.role };
  }

  leave(userId: string): EngineResult {
    const p = this.s.participants[userId];
    if (!p) return fail('not_found', 'Not in this session');
    this.s.queue = this.s.queue.filter((q) => q !== userId);
    if (userId === this.s.playerId) this.playerGone('left');
    // Votes already cast stay in the tally: leaving never changes a result.
    if (this.s.participants[userId]) delete this.s.participants[userId];
    this.emit('left', { userId });
    return { ok: true };
  }

  setPresence(userId: string, online: boolean): void {
    const p = this.s.participants[userId];
    if (!p || p.online === online) return;
    p.online = online;
    if (userId === this.s.playerId) {
      const sensitive = ATTEMPT_PHASES.includes(this.s.phase);
      this.s.playerGraceUntil = !online && sensitive ? this.deps.now() + this.t.graceMs : null;
    }
    this.emit('presence', { userId, online });
  }

  private playerGone(reason: string): void {
    const ph = this.s.phase;
    if (ph === 'LIVE_ROUND' || ph === 'SUBMISSION' || ph === 'AUDIENCE_VERDICT') {
      this.finalizeRound('abandoned', false);
      this.vacatePlayer();
    } else if (ph === 'SESSION_END') {
      /* nothing to do */
    } else {
      this.toLobby(reason, true);
    }
  }

  // ---- stage queue -----------------------------------------------------------------------------------------

  requestStage(actor: Actor): EngineResult {
    const p = this.who(actor);
    if (!p) return fail('not_found', 'Join the session first');
    if (p.role !== 'watcher') return fail('invalid', 'You are already on stage');
    if (this.s.phase === 'SESSION_END') return fail('ended', 'This session has ended');
    if (!this.s.queue.includes(p.id)) { this.s.queue.push(p.id); this.emit('queue', { userId: p.id }); }
    return { ok: true };
  }

  cancelStageRequest(actor: Actor): EngineResult {
    const p = this.who(actor);
    if (!p) return fail('not_found', 'Join the session first');
    this.s.queue = this.s.queue.filter((q) => q !== p.id);
    this.emit('queue', { userId: p.id });
    return { ok: true };
  }

  /** Hand the stage to the next volunteer. Only between rounds. */
  handoff(actor: Actor, toUserId?: string): EngineResult<{ playerId: string }> {
    if (!this.isHostOrPlayer(actor)) return fail('forbidden', 'Only the host or the Player can hand off the stage');
    if (this.s.phase !== 'ROUND_RESULT' && this.s.phase !== 'LOBBY') return fail('bad_phase', 'Hand-off is only possible between rounds');
    const target = toUserId ?? this.s.queue[0];
    if (!target || !this.s.queue.includes(target) || !this.s.participants[target]) return fail('no_candidate', 'Nobody is waiting for the stage');
    const prev = this.s.playerId;
    this.vacatePlayer();
    this.s.queue = this.s.queue.filter((q) => q !== target);
    this.s.participants[target]!.role = 'player';
    this.s.playerId = target;
    this.s.streamCut = false;
    this.invalidateGeneration();
    this.s.round = null; this.s.playerGraceUntil = null;
    this.setPhase('LOBBY', null);
    this.emit('handoff', { from: prev, to: target });
    return { ok: true, playerId: target };
  }

  // ---- the run ---------------------------------------------------------------------------------------------

  startRun(actor: Actor): EngineResult {
    if (!this.isHostOrPlayer(actor)) return fail('forbidden', 'Only the host or the Player can start a run');
    if (this.s.phase !== 'LOBBY') return fail('bad_phase', 'A run is already in progress');
    const pl = this.s.playerId ? this.s.participants[this.s.playerId] : undefined;
    if (!pl) return fail('no_candidate', 'Nobody is on stage yet');
    if (!pl.online) return fail('invalid', 'The Player is offline');
    if (this.s.streamCut) return fail('stream_cut', 'The stream was cut by a moderator');
    this.setPhase('READY_CHECK', this.deps.now() + this.t.readyMs);
    return { ok: true };
  }

  playerReady(actor: Actor, boundaries: unknown): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can confirm');
    if (this.s.phase !== 'READY_CHECK') return fail('bad_phase', 'Not in the ready check');
    // The Player's own boundaries come from the client and are sanitised; the session's audience is decided by the server.
    // In a teen session the teen floor is added on top, so no client can ask for anything below it.
    this.s.boundaries = withAudience(sanitizeBoundaries(boundaries), this.s.config.band);
    this.beginGeneration(true);
    return { ok: true };
  }

  /** System only: publish the five validated options. Re-validates every option itself. */
  publishOptions(actor: Actor, options: Challenge[], token: number): EngineResult {
    if (actor.kind !== 'system') return fail('forbidden', 'Only the server can publish options');
    if (this.s.phase !== 'CHALLENGE_GENERATION' || token !== this.s.generation.token) return fail('stale', 'Those options are no longer wanted');
    if (!Array.isArray(options) || options.length !== 5) return fail('invalid', 'Exactly five options are required');
    const ids = new Set(options.map((o) => o?.id));
    if (ids.size !== 5) return fail('invalid', 'Option ids must be unique');
    for (const o of options) {
      if (!o || typeof o.id !== 'string' || !this.deps.approve(o, this.s.boundaries)) return fail('unapproved_challenge', 'An option failed validation');
    }
    const r = this.s.round!;
    r.options = structuredClone(options);
    r.votes = {}; r.voteAt = {};
    this.setPhase('CHALLENGE_VOTE', this.deps.now() + this.t.voteMs);
    this.emit('options', { round: r.n });
    return { ok: true };
  }

  castVote(actor: Actor, idx: unknown): EngineResult<{ duplicate: boolean }> {
    const p = this.who(actor);
    if (!p) return fail('not_found', 'Join the session first');
    if (p.role !== 'watcher') return fail('forbidden', 'The Player does not vote on their own dare');
    if (this.s.phase !== 'CHALLENGE_VOTE') return fail('bad_phase', 'Voting is not open');
    const now = this.deps.now();
    if (this.s.phaseDeadline !== null && now >= this.s.phaseDeadline) return fail('vote_closed', 'Voting has closed');
    const r = this.s.round!;
    if (typeof idx !== 'number' || !Number.isInteger(idx) || idx < 0 || idx >= r.options.length) return fail('invalid', 'Unknown option');
    const prev = r.votes[p.id];
    if (prev !== undefined) return prev === idx ? { ok: true, duplicate: true } : fail('already_voted', 'You have already voted');
    r.votes[p.id] = idx; r.voteAt[p.id] = now;
    p.votesCast++;
    this.emit('vote', { round: r.n });
    this.maybeEarlyLock(now);
    return { ok: true, duplicate: false };
  }

  private maybeEarlyLock(now: number): void {
    if (this.s.phase !== 'CHALLENGE_VOTE') return;
    if (now - this.s.phaseStartedAt < MIN_EARLY_LOCK_MS) return;
    const online = Object.values(this.s.participants).filter((p) => p.role === 'watcher' && p.online);
    const r = this.s.round!;
    if (online.length > 0 && online.every((p) => r.votes[p.id] !== undefined)) this.lockVote();
  }

  private lockVote(): void {
    const r = this.s.round!;
    const w = pickWinner(r.votes, r.voteAt, r.options.length, this.deps.rng);
    r.chosenIdx = w.idx; r.chosenBy = w.by; r.finalTally = w.tally;
    for (const [uid, idx] of Object.entries(r.votes)) {
      const p = this.s.participants[uid];
      if (!r.voteAwarded[uid]) { r.voteAwarded[uid] = true; this.award(uid, POINTS.vote); }
      if (idx === w.idx) { this.award(uid, POINTS.calledIt); if (p) p.calledIt++; }
    }
    const title = r.options[w.idx]!.title;
    this.s.recentTitles = [...this.s.recentTitles, title].slice(-RECENT_TITLES);
    this.setPhase('PLAYER_REVIEW', this.deps.now() + this.t.reviewMs);
    this.emit('vote:locked', { round: r.n, idx: w.idx, tally: w.tally, by: w.by });
  }

  accept(actor: Actor): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can accept');
    if (this.s.phase !== 'PLAYER_REVIEW') return fail('bad_phase', 'There is nothing to accept');
    const r = this.s.round!; const c = r.options[r.chosenIdx!]!;
    const now = this.deps.now();
    r.startedAt = now; r.deadline = now + c.durationSeconds * 1000;
    if (this.s.config.twist && c.durationSeconds >= 40) {
      const options = buildTwistOptions(c, this.s.boundaries, this.deps.rng);
      if (options.length >= 2) {
        const opensAt = now + Math.round(c.durationSeconds * 1000 * 0.4);
        r.twist = { status: 'pending', options, votes: {}, voteAt: {}, opensAt, closesAt: opensAt + this.t.twistVoteMs, applied: null };
      }
    }
    this.setPhase('LIVE_ROUND', r.deadline);
    this.emit('accepted', { round: r.n, challengeId: c.id });
    return { ok: true };
  }

  pass(actor: Actor): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can pass');
    if (this.s.phase !== 'PLAYER_REVIEW') return fail('bad_phase', 'There is nothing to pass on');
    this.doPass('player');
    return { ok: true };
  }

  private doPass(by: 'player' | 'timeout'): void {
    const r = this.s.round!;
    r.passes++;
    this.emit('passed', { round: r.n, by });
    this.beginGeneration(false);   // fresh options, same round, no penalty
  }

  /** Safety Stop: always available to the Player during an attempt. Zero points, streak untouched, never a penalty. */
  safetyStop(actor: Actor): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can use the Safety Stop');
    if (!ATTEMPT_PHASES.includes(this.s.phase)) return fail('bad_phase', 'The Safety Stop is not needed right now');
    this.invalidateGeneration();
    if (!this.s.round) this.s.round = this.newRound();
    this.emit('safety:stop', { round: this.s.round.n });
    this.finalizeRound('safety_stop', false);
    return { ok: true };
  }

  finish(actor: Actor): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can finish');
    if (this.s.phase !== 'LIVE_ROUND') return fail('bad_phase', 'There is no attempt to finish');
    this.endAttempt();
    return { ok: true };
  }

  private endAttempt(): void {
    const r = this.s.round!;
    r.endedAt = this.deps.now();
    if (r.twist && r.twist.status !== 'closed') this.closeTwist();
    this.setPhase('SUBMISSION', this.deps.now() + this.t.submissionMs);
  }

  submit(actor: Actor, note?: unknown): EngineResult {
    if (!this.isPlayer(actor)) return fail('forbidden', 'Only the Player can submit');
    if (this.s.phase !== 'SUBMISSION') return fail('bad_phase', 'Not accepting a submission');
    if (note !== undefined && note !== null && typeof note !== 'string') return fail('invalid', 'Note must be text');
    this.toVerdict(typeof note === 'string' ? note.replace(/\s+/g, ' ').trim().slice(0, NOTE_MAX) : null);
    return { ok: true };
  }

  private toVerdict(note: string | null): void {
    this.s.round!.note = note || null;
    this.emit('attempt:submitted', { round: this.s.round!.n });
    this.setPhase('AUDIENCE_VERDICT', this.deps.now() + this.t.verdictMs);
  }

  castVerdict(actor: Actor, completed: unknown): EngineResult<{ duplicate: boolean }> {
    const p = this.who(actor);
    if (!p) return fail('not_found', 'Join the session first');
    if (p.role !== 'watcher') return fail('forbidden', 'The Player does not judge their own attempt');
    if (this.s.phase !== 'AUDIENCE_VERDICT') return fail('bad_phase', 'Judging is not open');
    if (this.s.phaseDeadline !== null && this.deps.now() >= this.s.phaseDeadline) return fail('vote_closed', 'Judging has closed');
    if (typeof completed !== 'boolean') return fail('invalid', 'Verdict must be true or false');
    const r = this.s.round!; const prev = r.verdicts[p.id];
    if (prev !== undefined) return prev === completed ? { ok: true, duplicate: true } : fail('already_voted', 'You have already judged');
    r.verdicts[p.id] = completed;
    this.emit('verdict:cast', { round: r.n });
    return { ok: true, duplicate: false };
  }

  castTwistVote(actor: Actor, idx: unknown): EngineResult<{ duplicate: boolean }> {
    const p = this.who(actor);
    if (!p) return fail('not_found', 'Join the session first');
    if (p.role !== 'watcher') return fail('forbidden', 'The Player does not vote on the twist');
    const tw = this.s.round?.twist;
    if (this.s.phase !== 'LIVE_ROUND' || !tw || tw.status !== 'open') return fail('bad_phase', 'The twist vote is not open');
    if (this.deps.now() >= tw.closesAt) return fail('vote_closed', 'The twist vote has closed');
    if (typeof idx !== 'number' || !Number.isInteger(idx) || idx < 0 || idx >= tw.options.length) return fail('invalid', 'Unknown twist');
    const prev = tw.votes[p.id];
    if (prev !== undefined) return prev === idx ? { ok: true, duplicate: true } : fail('already_voted', 'You have already voted');
    tw.votes[p.id] = idx; tw.voteAt[p.id] = this.deps.now();
    this.emit('twist:vote', { round: this.s.round!.n });
    return { ok: true, duplicate: false };
  }

  private closeTwist(): void {
    const r = this.s.round!; const tw = r.twist!;
    tw.status = 'closed';
    const w = pickWinner(tw.votes, tw.voteAt, tw.options.length, () => 0);
    if (w.by === 'vote') {
      tw.applied = tw.options[w.idx]!;
      for (const [uid, idx] of Object.entries(tw.votes)) if (idx === w.idx) this.award(uid, POINTS.twistMatch);
    }
    this.emit('twist:closed', { round: r.n, applied: tw.applied?.id ?? null, tally: w.tally });
  }

  private closeVerdict(): void {
    const r = this.s.round!;
    r.verdictClosed = true;
    const vals = Object.values(r.verdicts);
    const yes = vals.filter(Boolean).length, no = vals.length - yes;
    const judged = vals.length > 0;
    const completed = !judged || yes >= no;     // a tie gives the Player the benefit of the doubt
    if (judged) for (const [uid, v] of Object.entries(r.verdicts)) if (v === completed) this.award(uid, POINTS.verdictMatch);
    this.finalizeRound(completed ? 'completed' : 'failed', judged);
  }

  private finalizeRound(outcome: Outcome, judged: boolean): void {
    const r = this.s.round ?? (this.s.round = this.newRound());
    const pl = this.s.playerId ? this.s.participants[this.s.playerId] : undefined;
    const c = r.chosenIdx !== null ? r.options[r.chosenIdx] ?? null : null;
    const vals = Object.values(r.verdicts);
    const yes = vals.filter(Boolean).length;
    let pts = 0;
    if (pl) {
      if (outcome === 'completed') {
        pts = playerPoints(c?.difficulty ?? 1, pl.streak, judged);
        pl.streak++; pl.roundsCompleted++; this.s.completedCount++;
      } else if (outcome === 'failed') {
        pl.streak = 0;
      }   // safety_stop, abandoned and moderated never touch the streak or the score
      if (r.startedAt !== null) pl.roundsPlayed++;
      pl.score += pts;
    }
    const res: RoundResult = {
      round: r.n, playerId: pl?.id ?? this.s.playerId ?? '', playerHandle: pl?.handle ?? '', challengeId: c?.id ?? null,
      challengeTitle: c?.title ?? null, difficulty: c?.difficulty ?? null, outcome, judged, yes, no: vals.length - yes,
      playerPoints: pts, streak: pl?.streak ?? 0, awards: { ...r.awards }, passes: r.passes, twist: r.twist?.applied?.id ?? null, at: this.deps.now(),
    };
    r.result = res;
    this.s.history = [...this.s.history, res].slice(-HISTORY_LIMIT);
    this.s.playerGraceUntil = null;
    this.setPhase('ROUND_RESULT', this.deps.now() + this.t.resultMs);
    this.emit('round:result', { round: r.n, outcome });
  }

  next(actor: Actor): EngineResult {
    if (!this.isHostOrPlayer(actor)) return fail('forbidden', 'Only the host or the Player can continue');
    if (this.s.phase !== 'ROUND_RESULT') return fail('bad_phase', 'The round is not finished');
    if (this.s.streamCut) return fail('stream_cut', 'The stream was cut by a moderator');
    const pl = this.s.playerId ? this.s.participants[this.s.playerId] : undefined;
    if (!pl || !pl.online) return fail('invalid', 'The Player is not available');
    this.beginGeneration(true);
    return { ok: true };
  }

  end(actor: Actor): EngineResult {
    if (!this.isHostOrPlayer(actor)) return fail('forbidden', 'Only the host or the Player can end the session');
    if (this.s.phase === 'SESSION_END') return fail('ended', 'Already ended');
    this.endSession('host_ended');
    return { ok: true };
  }

  private endSession(reason: string): void {
    this.invalidateGeneration();
    this.s.endedReason = reason; this.s.playerGraceUntil = null;
    this.setPhase('SESSION_END', null);
    this.emit('session:ended', { reason });
  }

  // ---- moderation (takes precedence over ordinary progression) --------------------------------------------

  modEnd(actor: Actor): EngineResult {
    if (actor.kind !== 'moderator') return fail('forbidden', 'Moderators only');
    if (this.s.phase === 'SESSION_END') return fail('ended', 'Already ended');
    if (this.s.playerId) this.effects.push({ type: 'cut_stream', playerId: this.s.playerId });
    this.endSession('moderator_ended');
    return { ok: true };
  }

  modCutStream(actor: Actor): EngineResult {
    if (actor.kind !== 'moderator') return fail('forbidden', 'Moderators only');
    if (!this.s.playerId) return fail('no_candidate', 'Nobody is on stage');
    this.s.streamCut = true;
    this.effects.push({ type: 'cut_stream', playerId: this.s.playerId });
    this.emit('stream:cut', {});
    if (ATTEMPT_PHASES.includes(this.s.phase) || this.s.phase === 'AUDIENCE_VERDICT') {
      this.invalidateGeneration();
      this.finalizeRound('moderated', false);
    }
    return { ok: true };
  }

  modKick(actor: Actor, userId: string): EngineResult {
    if (actor.kind !== 'moderator') return fail('forbidden', 'Moderators only');
    if (!this.s.banned.includes(userId)) this.s.banned.push(userId);
    if (this.s.participants[userId]) {
      if (userId === this.s.config.hostId) return fail('forbidden', 'Use modEnd to close a session');
      this.leave(userId);
    }
    return { ok: true };
  }

  // ---- time ------------------------------------------------------------------------------------------------

  /** System only: process every deadline that has passed. Idempotent: calling it twice changes nothing the second time. */
  tick(): boolean {
    let changed = false;
    for (let i = 0; i < 16; i++) {
      if (!this.step()) break;
      changed = true;
    }
    return changed;
  }

  private step(): boolean {
    const now = this.deps.now(); const s = this.s;
    if (s.phase === 'SESSION_END') return false;

    const pl = s.playerId ? s.participants[s.playerId] : undefined;
    if (s.playerGraceUntil !== null && now >= s.playerGraceUntil) {
      if (pl && !pl.online) { this.playerGone('player_disconnected'); return true; }
      s.playerGraceUntil = null;
    }

    const dl = s.phaseDeadline;
    switch (s.phase) {
      case 'READY_CHECK':
        if (dl !== null && now >= dl) { this.toLobby('ready_timeout'); return true; }
        return false;
      case 'CHALLENGE_GENERATION':
        if (dl !== null && now >= dl) {
          if (s.generation.attempts < 1) {
            s.generation.attempts++; s.phaseDeadline = now + this.t.fallbackWaitMs;
            this.effects.push({ type: 'generate', token: s.generation.token, round: s.round!.n, difficulty: this.targetDifficulty(), boundaries: structuredClone(s.boundaries), recentTitles: [...s.recentTitles], forceFallback: true });
            this.emit('generation:timeout', {});
          } else this.toLobby('generation_failed');
          return true;
        }
        return false;
      case 'CHALLENGE_VOTE':
        if (dl !== null && now >= dl) { this.lockVote(); return true; }
        return false;
      case 'PLAYER_REVIEW':
        if (dl !== null && now >= dl) { this.doPass('timeout'); return true; }
        return false;
      case 'LIVE_ROUND': {
        const tw = s.round!.twist;
        if (tw && tw.status === 'pending' && now >= tw.opensAt) { tw.status = 'open'; this.emit('twist:open', { options: tw.options.length }); return true; }
        if (tw && tw.status === 'open' && now >= tw.closesAt) { this.closeTwist(); return true; }
        if (s.round!.deadline !== null && now >= s.round!.deadline) { this.endAttempt(); return true; }
        return false;
      }
      case 'SUBMISSION':
        if (dl !== null && now >= dl) { this.toVerdict(null); return true; }
        return false;
      case 'AUDIENCE_VERDICT':
        if (dl !== null && now >= dl) { this.closeVerdict(); return true; }
        return false;
      case 'ROUND_RESULT':
        if (dl !== null && now >= dl) { this.toLobby('idle'); return true; }
        return false;
      default:
        return false;
    }
  }

  /** Earliest moment `tick()` has something to do. The runtime sleeps until then. */
  nextDeadline(): number | null {
    const c: number[] = [];
    if (this.s.phaseDeadline !== null) c.push(this.s.phaseDeadline);
    if (this.s.playerGraceUntil !== null) c.push(this.s.playerGraceUntil);
    const tw = this.s.round?.twist;
    if (this.s.phase === 'LIVE_ROUND' && tw) { if (tw.status === 'pending') c.push(tw.opensAt); if (tw.status === 'open') c.push(tw.closesAt); }
    return c.length ? Math.min(...c) : null;
  }
}
