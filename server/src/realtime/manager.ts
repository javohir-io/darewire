// SessionManager: owns every live GameSession in memory and wires the pure engine to the outside world:
// timers, the AI Director, persistence, WebSocket broadcast, LiveKit and simulated test audiences.
// The engine decides; this file only executes.
import { randomUUID } from 'node:crypto';
import { GameSession, viewFor, type Actor, type EngineDeps, type EngineEvent, type EngineResult, type Effect } from '../engine/index.ts';
import { approveChallenge } from '../director/approve.ts';
import type { Director } from '../director/director.ts';
import type { Media } from '../media/livekit.ts';
import { cleanText } from '../policy/parse.ts';
import { sanitizeBoundaries } from '../policy/types.ts';
import { bandOf, isStaff } from '../profile/age.ts';
import type { Storage } from '../media/storage.ts';
import type { Recorder } from './recorder.ts';
import type { Clip, Profile, Repo, UserRole } from '../store/types.ts';
import { log } from '../util/log.ts';
import { roomCode } from '../util/ids.ts';
import { RateLimiter } from '../util/ratelimit.ts';
import { REACTIONS, cleanChat, type ChatMsg } from './chat.ts';

export interface Client {
  id: string;
  userId: string;
  role: UserRole;
  observer: boolean;
  blocked: Set<string>;
  send(msg: { type: string; id?: string; rev?: number; data?: unknown }): void;
  close(code: number, reason: string): void;
}

interface Runtime {
  game: GameSession;
  visibility: 'public' | 'private';
  clients: Set<Client>;
  timer: ReturnType<typeof setTimeout> | null;
  stateTimer: ReturnType<typeof setTimeout> | null;
  saveTimer: ReturnType<typeof setTimeout> | null;
  chat: ChatMsg[];
  lastPlayerId: string | null;
  bots: Set<string>;
  botKey: string;
  allowClips: boolean;
  offers: Map<string, Clip>;
  lastActivity: number;
}

export interface Deps {
  repo: Repo;
  director: Director;
  media: Media | null;
  storage?: Storage | null;
  now?: () => number;
  rng?: () => number;
}

export type CmdResult = { ok: true; data?: unknown } | { ok: false; code: string; message: string };

// Events that only change counters: their state push is coalesced to keep large audiences cheap.
const SOFT = new Set(['vote', 'twist:vote', 'verdict:cast', 'presence', 'queue', 'joined', 'left']);
// Engine event -> wire event name (names follow docs/api.md).
const FORWARD: Record<string, string> = {
  options: 'challenge:options', 'vote:locked': 'vote:locked', accepted: 'round:started', passed: 'challenge:passed',
  'attempt:submitted': 'attempt:submitted', 'round:result': 'verdict:finalized', 'safety:stop': 'safety:stop',
  'session:ended': 'session:ended', 'twist:open': 'twist:open', 'twist:closed': 'twist:closed', 'stream:cut': 'stream:cut',
};
const BOT_NAMES = ['volt', 'ember', 'static', 'relay', 'coil', 'arc', 'pulse', 'diode', 'spark', 'node', 'fuse', 'ohm'];

export class SessionManager {
  private sessions = new Map<string, Runtime>();
  private repo: Repo;
  private director: Director;
  private media: Media | null;
  private storage: Storage | null;
  private recorder: Recorder | null = null;
  private now: () => number;
  private rng: () => number;
  private chatLimit = new RateLimiter(3, 0.6);
  private reactLimit = new RateLimiter(8, 4);
  private sweeper: ReturnType<typeof setInterval> | null = null;

  constructor(d: Deps) {
    this.repo = d.repo; this.director = d.director; this.media = d.media; this.storage = d.storage ?? null;
    this.now = d.now ?? Date.now; this.rng = d.rng ?? Math.random;
  }

  private deps(): EngineDeps { return { now: this.now, rng: this.rng, uid: randomUUID, approve: approveChallenge }; }

  // ---- lifecycle ------------------------------------------------------------------------------------------

  async restore(): Promise<number> {
    const rows = await this.repo.loadActiveSessions();
    for (const { state, visibility } of rows) {
      const game = GameSession.restore(state, this.deps());
      for (const p of Object.values(game.s.participants)) p.online = false;   // nobody is connected after a restart
      const rt = this.newRuntime(game, visibility);
      this.sessions.set(game.s.id, rt);
      game.tick();
      this.after(rt, true);
    }
    return rows.length;
  }

  startSweeper(): void {
    this.sweeper = setInterval(() => this.sweep(), 60_000);
    this.sweeper.unref?.();
  }

  private sweep(): void {
    void this.repo.expireAwaiting(24 * 3_600_000).then((gone) => { for (const c of gone) void this.storage?.remove(c.storagePath); }).catch(() => undefined);
    const t = this.now();
    for (const [id, rt] of this.sessions) {
      const s = rt.game.s;
      if (s.phase === 'SESSION_END' && t - rt.lastActivity > 10 * 60_000) { this.dispose(rt); this.sessions.delete(id); continue; }
      if (s.phase === 'LOBBY' && rt.clients.size === 0 && !rt.bots.size && t - rt.lastActivity > 30 * 60_000) {
        rt.game.end({ kind: 'user', id: s.config.hostId }); this.after(rt, true);
      }
    }
  }

  async shutdown(): Promise<void> {
    if (this.sweeper) clearInterval(this.sweeper);
    for (const rt of this.sessions.values()) {
      this.dispose(rt);
      await this.repo.saveSession(rt.game.snapshot(), rt.visibility).catch(() => undefined);
    }
  }

  private dispose(rt: Runtime): void {
    for (const t of [rt.timer, rt.stateTimer, rt.saveTimer]) if (t) clearTimeout(t);
    rt.timer = rt.stateTimer = rt.saveTimer = null;
  }

  private newRuntime(game: GameSession, visibility: 'public' | 'private'): Runtime {
    return { game, visibility, clients: new Set(), timer: null, stateTimer: null, saveTimer: null, chat: [], lastPlayerId: game.s.playerId, bots: new Set(), botKey: '', allowClips: false, offers: new Map(), lastActivity: this.now() };
  }

  // ---- sessions -------------------------------------------------------------------------------------------

  async create(host: Profile, input: { title: string; twist: boolean; visibility: 'public' | 'private'; hostPlays: boolean; timings?: Partial<import('../engine/types.ts').Timings> }): Promise<{ id: string; code: string }> {
    let code = roomCode();
    while ([...this.sessions.values()].some((r) => r.game.s.code === code)) code = roomCode();
    const game = GameSession.create({ id: randomUUID(), code, title: cleanText(input.title), hostId: host.id, band: bandOf(host) ?? 'adult', twist: input.twist, timings: input.timings }, this.deps());
    const rt = this.newRuntime(game, input.visibility);
    this.sessions.set(game.s.id, rt);
    game.join({ kind: 'user', id: host.id }, { handle: host.handle ?? 'host', avatar: host.avatar }, input.hostPlays ? 'player' : 'watcher');
    game.setPresence(host.id, false);    // becomes online when the host's socket connects
    this.after(rt, true);
    return { id: game.s.id, code };
  }

  get(id: string): Runtime | undefined { return this.sessions.get(id); }
  /** Finds a live session by its code. When `viewer` is given, a session of the other age band is treated as not existing. */
  byCode(code: string, viewer?: Pick<Profile, 'birthDate' | 'role'>): Runtime | undefined {
    const c = code.trim().toUpperCase();
    return [...this.sessions.values()].find((r) => r.game.s.code === c && r.game.s.phase !== 'SESSION_END' && (!viewer || this.visibleTo(viewer, r)));
  }

  /** Teens and adults never share a session. Staff (moderators and admins) may enter any session. */
  private visibleTo(viewer: Pick<Profile, 'birthDate' | 'role'>, rt: Runtime): boolean {
    return isStaff(viewer) || bandOf(viewer) === (rt.game.s.config.band ?? 'adult');
  }
  hostedBy(userId: string): string | null { for (const r of this.sessions.values()) if (r.game.s.config.hostId === userId && r.game.s.phase !== 'SESSION_END') return r.game.s.id; return null; }

  listPublic(viewer?: Pick<Profile, 'birthDate' | 'role'>) {
    return [...this.sessions.values()]
      .filter((r) => r.visibility === 'public' && r.game.s.phase !== 'SESSION_END' && (!viewer || this.visibleTo(viewer, r)))
      .map((r) => {
        const s = r.game.s; const p = s.playerId ? s.participants[s.playerId] : null;
        const chosen = s.round && s.round.chosenIdx !== null ? s.round.options[s.round.chosenIdx] ?? null : null;
        const dare = chosen && ['PLAYER_REVIEW', 'LIVE_ROUND', 'SUBMISSION', 'AUDIENCE_VERDICT'].includes(s.phase) ? { title: chosen.title, difficulty: chosen.difficulty, category: chosen.category } : null;
        return { id: s.id, code: s.code, title: s.config.title, phase: s.phase, watchers: Object.values(s.participants).filter((x) => x.role === 'watcher').length,
          player: p ? { id: p.id, handle: p.handle, avatar: p.avatar, streak: p.streak } : null, round: s.roundNumber, twist: s.config.twist, createdAt: s.createdAt, dare };
      })
      .sort((a, b) => b.watchers - a.watchers);
  }

  listAll() { return [...this.sessions.values()].map((r) => ({ id: r.game.s.id, code: r.game.s.code, title: r.game.s.config.title, phase: r.game.s.phase, visibility: r.visibility, clients: r.clients.size, hostId: r.game.s.config.hostId })); }

  // ---- connections ----------------------------------------------------------------------------------------

  async connect(client: Client, sessionId: string, profile: Profile, want: 'watcher' | 'player' | 'observer'): Promise<CmdResult> {
    const rt = this.sessions.get(sessionId);
    if (!rt) return { ok: false, code: 'not_found', message: 'Session not found' };
    const s = rt.game.s;
    if (want === 'observer') {
      if (client.role === 'user') return { ok: false, code: 'forbidden', message: 'Moderators only' };
      client.observer = true;
    } else {
      if (s.phase === 'SESSION_END') return { ok: false, code: 'ended', message: 'This session has ended' };
      // A session of the other age band answers exactly like one that does not exist, so nothing about it leaks.
      if (!this.visibleTo(profile, rt)) return { ok: false, code: 'not_found', message: 'Session not found' };
      const others = [s.config.hostId, s.playerId].filter((x): x is string => !!x && x !== client.userId);
      for (const o of others) if (await this.repo.blockedEitherWay(client.userId, o)) return { ok: false, code: 'blocked', message: 'You cannot join this session' };
      const r = rt.game.join({ kind: 'user', id: client.userId }, { handle: profile.handle ?? 'player', avatar: profile.avatar }, want);
      if (!r.ok) return { ok: false, code: r.code, message: r.message };
    }
    client.blocked = new Set(await this.repo.blockedIds(client.userId));
    rt.clients.add(client);
    rt.lastActivity = this.now();
    this.sendState(rt, client);
    const offer = rt.offers.get(client.userId);
    if (offer) client.send({ type: 'clip:ready', data: { id: offer.id, title: offer.title, durationMs: offer.durationMs } });
    client.send({ type: 'chat:history', data: rt.chat.filter((m) => !client.blocked.has(m.userId)).slice(-30) });
    this.after(rt, false);
    return { ok: true };
  }

  disconnect(client: Client, sessionId: string): void {
    const rt = this.sessions.get(sessionId);
    if (!rt) return;
    rt.clients.delete(client);
    if (client.observer) return;
    const stillHere = [...rt.clients].some((c) => c.userId === client.userId && !c.observer);
    if (!stillHere) { rt.game.setPresence(client.userId, false); this.after(rt, false); }
  }

  /** Called when an account is deleted: leave every session and close every socket. */
  dropUser(userId: string): void {
    for (const rt of this.sessions.values()) {
      for (const c of [...rt.clients]) if (c.userId === userId) { c.close(4003, 'account_deleted'); rt.clients.delete(c); }
      if (rt.game.s.participants[userId]) { rt.game.leave(userId); this.after(rt, true); }
    }
  }

  // ---- commands -------------------------------------------------------------------------------------------

  async command(client: Client, sessionId: string, type: string, data: any): Promise<CmdResult> {
    const rt = this.sessions.get(sessionId);
    if (!rt) return { ok: false, code: 'not_found', message: 'Session not found' };
    rt.lastActivity = this.now();
    const g = rt.game;
    const actor: Actor = { kind: 'user', id: client.userId };
    const modActor: Actor = { kind: 'moderator', id: client.userId };
    const isMod = client.role === 'moderator' || client.role === 'admin';
    const d = data && typeof data === 'object' ? data : {};
    let res: EngineResult<any>;

    switch (type) {
      case 'vote:cast': res = g.castVote(actor, d.option); break;
      case 'twist:vote': res = g.castTwistVote(actor, d.option); break;
      case 'verdict:cast': res = g.castVerdict(actor, d.completed); break;
      case 'session:start': res = g.startRun(actor); break;
      case 'player:ready': {
        rt.allowClips = d.allowClips === true;   // per-run consent to record clips
        const prof = await this.repo.getProfile(client.userId);
        // Boundaries come from the Player's saved profile unless they sent an explicit override for this run.
        res = g.playerReady(actor, d.boundaries ? sanitizeBoundaries(d.boundaries) : prof?.boundaries);
        break;
      }
      case 'challenge:accept': res = g.accept(actor); break;
      case 'challenge:pass': res = g.pass(actor); break;
      case 'safety:stop': res = g.safetyStop(actor); break;
      case 'attempt:finish': res = g.finish(actor); break;
      case 'attempt:submit': res = g.submit(actor, d.note); break;
      case 'round:next': res = g.next(actor); break;
      case 'session:end': res = g.end(actor); break;
      case 'stage:request': res = g.requestStage(actor); break;
      case 'stage:cancel': res = g.cancelStageRequest(actor); break;
      case 'stage:handoff': res = g.handoff(actor, typeof d.userId === 'string' ? d.userId : undefined); break;
      case 'session:leave': { res = g.leave(client.userId); rt.clients.delete(client); break; }
      case 'chat:send': return this.chat(rt, client, d.text);
      case 'reaction:send': return this.react(rt, client, d.kind);
      case 'mod:end': if (!isMod) return forbidden(); res = g.modEnd(modActor); await this.audit(client, 'end_session', sessionId); break;
      case 'mod:cut': if (!isMod) return forbidden(); res = g.modCutStream(modActor); await this.audit(client, 'cut_stream', sessionId); break;
      case 'mod:kick': if (!isMod) return forbidden(); res = typeof d.userId === 'string' ? g.modKick(modActor, d.userId) : { ok: false, code: 'invalid', message: 'userId required' }; await this.audit(client, 'kick', sessionId, d.userId); break;
      case 'mod:chat:delete': if (!isMod) return forbidden(); this.broadcast(rt, { type: 'chat:deleted', data: { id: String(d.id) } }); rt.chat = rt.chat.filter((m) => m.id !== d.id); return { ok: true };
      case 'ping': return { ok: true };
      default: return { ok: false, code: 'unknown_command', message: 'Unknown command' };
    }
    this.after(rt, false);
    return res.ok ? { ok: true } : { ok: false, code: res.code, message: res.message };
  }

  private async audit(c: Client, action: string, sessionId: string, target?: string): Promise<void> {
    await this.repo.logModeration({ moderatorId: c.userId, action, sessionId, targetUserId: typeof target === 'string' ? target : undefined }).catch(() => undefined);
  }

  private chat(rt: Runtime, c: Client, raw: unknown): CmdResult {
    const p = rt.game.s.participants[c.userId];
    if (!p || c.observer) return { ok: false, code: 'forbidden', message: 'Join the session to chat' };
    if (!this.chatLimit.take(c.userId)) return { ok: false, code: 'rate_limited', message: 'Slow down' };
    const text = cleanChat(raw);
    if (!text) return { ok: false, code: 'invalid', message: 'Messages are 1-140 characters, with no links or contact details' };
    const msg: ChatMsg = { id: randomUUID(), userId: c.userId, handle: p.handle, text, at: this.now() };
    rt.chat.push(msg); if (rt.chat.length > 60) rt.chat.shift();
    for (const cl of rt.clients) if (!cl.blocked.has(c.userId)) cl.send({ type: 'chat:message', data: msg });
    return { ok: true };
  }

  private react(rt: Runtime, c: Client, kind: unknown): CmdResult {
    if (!rt.game.s.participants[c.userId] || c.observer) return { ok: false, code: 'forbidden', message: 'Join the session first' };
    if (typeof kind !== 'string' || !(REACTIONS as readonly string[]).includes(kind)) return { ok: false, code: 'invalid', message: 'Unknown reaction' };
    if (!this.reactLimit.take(c.userId)) return { ok: false, code: 'rate_limited', message: 'Slow down' };
    this.broadcast(rt, { type: 'reaction', data: { kind, from: c.userId } });
    return { ok: true };
  }

  // ---- moderation entry points used by REST --------------------------------------------------------------

  async moderate(sessionId: string, mod: Profile, action: 'end' | 'cut' | 'kick', target?: string): Promise<CmdResult> {
    const rt = this.sessions.get(sessionId);
    if (!rt) return { ok: false, code: 'not_found', message: 'Session not found' };
    const a: Actor = { kind: 'moderator', id: mod.id };
    const r = action === 'end' ? rt.game.modEnd(a) : action === 'cut' ? rt.game.modCutStream(a) : rt.game.modKick(a, target ?? '');
    await this.audit({ userId: mod.id } as Client, `${action}_session`, sessionId, target);
    this.after(rt, true);
    return r.ok ? { ok: true } : { ok: false, code: r.code, message: r.message };
  }

  // ---- media ----------------------------------------------------------------------------------------------

  async mediaToken(userId: string, handle: string, sessionId: string, role: UserRole): Promise<CmdResult> {
    if (!this.media) return { ok: false, code: 'media_unavailable', message: 'Live video is not configured on this server' };
    const rt = this.sessions.get(sessionId);
    if (!rt) return { ok: false, code: 'not_found', message: 'Session not found' };
    const s = rt.game.s;
    const isMember = !!s.participants[userId];
    const isObserver = role !== 'user';
    if (!isMember && !isObserver) return { ok: false, code: 'forbidden', message: 'Join the session first' };
    if (s.phase === 'SESSION_END') return { ok: false, code: 'ended', message: 'This session has ended' };
    const canPublish = userId === s.playerId && !s.streamCut;
    const token = await this.media.token(sessionId, userId, handle, canPublish);
    return { ok: true, data: { url: this.media.url, token, room: this.media.roomName(sessionId), canPublish } };
  }

  // ---- simulated audience (development and load demos only) ----------------------------------------------

  addBots(sessionId: string, n: number): number {
    const rt = this.sessions.get(sessionId);
    if (!rt) return 0;
    let added = 0;
    for (let i = 0; i < n; i++) {
      const id = `sim:${randomUUID().slice(0, 8)}`;
      const r = rt.game.join({ kind: 'user', id }, { handle: `sim_${BOT_NAMES[(rt.bots.size + i) % BOT_NAMES.length]}${rt.bots.size + i}`, avatar: ['a03', 'a01', 'a09', 'a02', 'a07'][i % 5]! });
      if (r.ok) { rt.bots.add(id); added++; }
    }
    this.after(rt, false);
    return added;
  }

  private botTurn(rt: Runtime): void {
    const s = rt.game.s;
    const key = `${s.phase}:${s.roundNumber}:${s.generation.token}:${s.round?.twist?.status ?? ''}`;
    if (!rt.bots.size || key === rt.botKey) return;
    rt.botKey = key;
    const act = (fn: (id: string) => void, maxMs: number) => {
      for (const id of rt.bots) { const t = setTimeout(() => { fn(id); this.after(rt, false); }, 500 + this.rng() * maxMs); t.unref?.(); }
    };
    if (s.phase === 'CHALLENGE_VOTE') act((id) => rt.game.castVote({ kind: 'user', id }, Math.floor(this.rng() * 5)), 12_000);
    else if (s.phase === 'AUDIENCE_VERDICT') act((id) => rt.game.castVerdict({ kind: 'user', id }, this.rng() < 0.75), 8_000);
    else if (s.phase === 'LIVE_ROUND' && s.round?.twist?.status === 'open') act((id) => rt.game.castTwistVote({ kind: 'user', id }, Math.floor(this.rng() * (s.round?.twist?.options.length ?? 1))), 5_000);
  }

  // ---- the heart: drain engine output, persist, broadcast, execute effects, re-arm the timer -------------

  private after(rt: Runtime, saveNow: boolean, fromTimer = false): void {
    const { events, effects } = rt.game.drain();
    if (events.length) {
      const hard = events.some((e) => !SOFT.has(e.type));
      this.persist(rt, events, saveNow || hard);
      this.forward(rt, events);
      this.record(rt, events);
      this.pushStates(rt, hard);
    }
    for (const fx of effects) this.execute(rt, fx);
    this.trackPlayer(rt);
    this.botTurn(rt);
    this.schedule(rt, fromTimer && events.length === 0);
  }

  /** Feed the clip recorder. Consent is reset whenever the stage changes hands. */
  private record(rt: Runtime, events: EngineEvent[]): void {
    const s = rt.game.s;
    if (events.some((e) => e.type === 'handoff')) rt.allowClips = false;
    if (!this.recorder) return;
    const pl = s.playerId ? s.participants[s.playerId] : undefined;
    const r = s.round; const c = r && r.chosenIdx !== null ? r.options[r.chosenIdx] : undefined;
    this.recorder.handle({
      sessionId: s.id, phase: s.phase, allowClips: rt.allowClips,
      player: pl ? { id: pl.id, handle: pl.handle, avatar: pl.avatar } : null,
      round: r && c ? { n: r.n, title: c.title, category: c.category, difficulty: c.difficulty, twist: r.twist?.applied?.id ?? null } : null,
    }, events);
  }

  setRecorder(r: Recorder): void { this.recorder = r; }

  /** A finished clip is waiting for the Player's decision. Held until they publish or discard, and re-sent on reconnect. */
  offerClip(sessionId: string, userId: string, clip: Clip): void {
    const rt = this.sessions.get(sessionId);
    if (!rt) { void this.storage?.remove(clip.storagePath); void this.repo.deleteClip(clip.id); return; }
    rt.offers.set(userId, clip);
    for (const c of rt.clients) if (c.userId === userId) c.send({ type: 'clip:ready', data: { id: clip.id, title: clip.title, durationMs: clip.durationMs } });
  }

  clearOffer(userId: string, clipId: string): void {
    for (const rt of this.sessions.values()) if (rt.offers.get(userId)?.id === clipId) rt.offers.delete(userId);
  }

  private persist(rt: Runtime, events: EngineEvent[], now: boolean): void {
    const s = rt.game.s;
    const loggable = events.filter((e) => e.type !== 'vote' && e.type !== 'twist:vote' && e.type !== 'verdict:cast' && e.type !== 'presence');
    if (loggable.length) void this.repo.appendEvents(s.id, loggable).catch((e) => log('warn', 'appendEvents failed', { err: String(e?.message ?? e) }));
    if (events.some((e) => e.type === 'round:result') && s.round?.result) {
      void this.repo.saveRound(s.id, structuredClone(s.round), s.round.result).catch((e) => log('error', 'saveRound failed', { err: String(e?.message ?? e) }));
    }
    const save = () => this.repo.saveSession(rt.game.snapshot(), rt.visibility).catch((e) => log('error', 'saveSession failed', { err: String(e?.message ?? e) }));
    if (now) { if (rt.saveTimer) { clearTimeout(rt.saveTimer); rt.saveTimer = null; } void save(); }
    else if (!rt.saveTimer) { rt.saveTimer = setTimeout(() => { rt.saveTimer = null; void save(); }, 2000); rt.saveTimer.unref?.(); }
  }

  private forward(rt: Runtime, events: EngineEvent[]): void {
    for (const e of events) {
      const name = FORWARD[e.type];
      if (name) this.broadcast(rt, { type: name, rev: e.rev, data: e.data });
      if (e.type === 'phase') this.broadcast(rt, { type: 'round:timer', rev: e.rev, data: { phase: rt.game.s.phase, deadline: rt.game.s.phaseDeadline, serverTime: this.now() } });
    }
  }

  private pushStates(rt: Runtime, immediate: boolean): void {
    if (immediate) {
      if (rt.stateTimer) { clearTimeout(rt.stateTimer); rt.stateTimer = null; }
      for (const c of rt.clients) this.sendState(rt, c);
      return;
    }
    if (rt.stateTimer) return;
    rt.stateTimer = setTimeout(() => { rt.stateTimer = null; for (const c of rt.clients) this.sendState(rt, c); }, 250);
    rt.stateTimer.unref?.();
  }

  private sendState(rt: Runtime, c: Client): void {
    const s = rt.game.s;
    c.send({ type: 'session:state', rev: s.rev, data: viewFor(s, c.observer ? null : c.userId, this.now()) });
  }

  private broadcast(rt: Runtime, msg: { type: string; rev?: number; data?: unknown }): void { for (const c of rt.clients) c.send(msg); }

  private execute(rt: Runtime, fx: Effect): void {
    const s = rt.game.s;
    if (fx.type === 'generate') {
      void (async () => {
        try {
          const res = await this.director.generate({ difficulty: fx.difficulty, boundaries: fx.boundaries, recentTitles: fx.recentTitles, forceFallback: fx.forceFallback });
          void this.repo.saveGeneration(s.id, fx.round, res.report).catch(() => undefined);
          log('info', 'director', { session: s.id, round: fx.round, ai: res.report.aiAccepted, fallback: res.report.fallbackUsed, rejected: res.report.rejected.length, reviewer: res.report.reviewer, ms: res.report.ms, err: res.report.error });
          if (res.options.length === 5) rt.game.publishOptions({ kind: 'system' }, res.options, fx.token);
        } catch (e) {
          log('error', 'generation failed', { session: s.id, err: e instanceof Error ? e.message : 'unknown' });
        }
        this.after(rt, false);
      })();
    } else if (fx.type === 'cut_stream') {
      void this.media?.cut(s.id, fx.playerId);
    }
  }

  /** When the Player changes (hand-off, leave, safety), revoke the previous Player's publish rights in LiveKit. */
  private trackPlayer(rt: Runtime): void {
    const now = rt.game.s.playerId;
    if (rt.lastPlayerId && rt.lastPlayerId !== now) void this.media?.revokePublish(rt.game.s.id, rt.lastPlayerId);
    if (rt.game.s.phase === 'SESSION_END' && this.media) void this.media.closeRoom(rt.game.s.id);
    rt.lastPlayerId = now;
  }

  private schedule(rt: Runtime, idleTick: boolean): void {
    if (rt.timer) { clearTimeout(rt.timer); rt.timer = null; }
    const d = rt.game.nextDeadline();
    if (d === null) return;
    let ms = Math.max(0, d - this.now()) + 5;
    if (idleTick) ms = Math.max(ms, 1000);    // guard: an overdue deadline that produced no transition must not spin
    rt.timer = setTimeout(() => { rt.timer = null; rt.game.tick(); this.after(rt, false, true); }, Math.min(ms, 2 ** 31 - 1));
    rt.timer.unref?.();
  }
}

const forbidden = (): CmdResult => ({ ok: false, code: 'forbidden', message: 'Moderators only' });
