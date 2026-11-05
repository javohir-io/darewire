import { randomUUID } from 'node:crypto';
import { DEFAULT_AVATAR } from '../util/ids.ts';
import { DEFAULT_BOUNDARIES, sanitizeBoundaries } from '../policy/types.ts';
import type { EngineEvent, EngineState, Round, RoundResult } from '../engine/index.ts';
import type { GenerationReport } from '../director/director.ts';
import { pairOf } from './types.ts';
import type { ChatMessage, Conversation, Notification, NotificationKind, UserStats, Clip, ClipStatus, Duel, FeedQuery, FeedRow, HandleHit, LeaderRow, LedgerEntry, LedgerKind, NewClip, NewLedgerEntry, Profile, Report, Repo, UserRole } from './types.ts';

/** Same ranking idea as the SQL: engagement divided by age (hours + 2) ^ 1.4. */
export const hotScore = (likes: number, views: number, publishedAtMs: number, nowMs: number) =>
  (likes * 3 + views * 0.2 + 1) / Math.pow((nowMs - publishedAtMs) / 3_600_000 + 2, 1.4);

export class MemoryRepo implements Repo {
  profiles = new Map<string, Profile>();
  sessions = new Map<string, { state: EngineState; visibility: 'public' | 'private' }>();
  results: { sessionId: string; result: RoundResult }[] = [];
  reports: Report[] = [];
  blocks = new Set<string>();
  moderation: unknown[] = [];
  events: { sessionId: string; e: EngineEvent }[] = [];
  clips = new Map<string, Clip>();
  likes = new Set<string>();
  seen = new Set<string>();
  clipReports = new Map<string, Set<string>>();
  clock: () => number = Date.now;
  avatars = new Map<string, { mime: string; data: Buffer; version: number }>();
  duels = new Map<string, Duel>();
  points: LedgerEntry[] = [];
  follows = new Set<string>();   // `${follower}>${followee}` in insertion order
  conversations = new Map<string, Conversation>();
  messages: ChatMessage[] = [];
  notifications: Notification[] = [];

  async getProfile(id: string) { return this.profiles.get(id) ?? null; }
  async ensureProfile(id: string) {
    let p = this.profiles.get(id);
    if (!p) { p = { id, handle: null, avatar: DEFAULT_AVATAR, birthDate: null, ageVerifiedAt: null, role: 'user', boundaries: { ...DEFAULT_BOUNDARIES }, bio: '', accent: 'neon', suspendedUntil: null, createdAt: new Date().toISOString() }; this.profiles.set(id, p); }
    return p;
  }
  async updateProfile(id: string, patch: Partial<Pick<Profile, 'handle' | 'avatar' | 'boundaries' | 'bio' | 'accent'>>) {
    const p = await this.ensureProfile(id);
    if (patch.handle !== undefined) {
      for (const o of this.profiles.values()) if (o.id !== id && o.handle === patch.handle) throw new Error('handle_taken');
      p.handle = patch.handle;
    }
    if (patch.avatar !== undefined) p.avatar = patch.avatar;
    if (patch.bio !== undefined) p.bio = patch.bio;
    if (patch.accent !== undefined) p.accent = patch.accent;
    if (patch.boundaries) p.boundaries = sanitizeBoundaries(patch.boundaries);
    return p;
  }
  async setAge(id: string, birthDate: string, verified = true) { const p = await this.ensureProfile(id); p.birthDate = birthDate; p.ageVerifiedAt = verified ? new Date().toISOString() : null; return p; }
  async setRole(id: string, role: UserRole) { (await this.ensureProfile(id)).role = role; }
  async suspend(id: string, until: string | null) { (await this.ensureProfile(id)).suspendedUntil = until; }
  async deleteUser(id: string) {
    this.profiles.delete(id); this.results = this.results.filter((r) => r.result.playerId !== id);
    this.avatars.delete(id); this.points = this.points.filter((e) => e.userId !== id);
    for (const [k, d] of this.duels) if (d.challengerId === id || d.targetId === id) this.duels.delete(k);
    for (const k of [...this.follows]) if (k.startsWith(`${id}>`) || k.endsWith(`>${id}`)) this.follows.delete(k);
    for (const [k, c] of this.conversations) if (c.userA === id || c.userB === id) { this.conversations.delete(k); this.messages = this.messages.filter((m) => m.conversationId !== k); }
    this.notifications = this.notifications.filter((n) => n.userId !== id && n.actorId !== id);
  }
  async searchHandles(prefix: string, limit: number, excludeIds: string[]): Promise<HandleHit[]> {
    const q = prefix.toLowerCase();
    return [...this.profiles.values()]
      .filter((p) => p.handle && p.ageVerifiedAt && p.handle.startsWith(q) && !excludeIds.includes(p.id))
      .sort((a, b) => a.handle!.length - b.handle!.length || a.handle!.localeCompare(b.handle!)).slice(0, limit)
      .map((p) => ({ id: p.id, handle: p.handle!, avatar: p.avatar }));
  }

  async setAvatarBlob(userId: string, mime: string, data: Buffer) { const version = this.clock(); this.avatars.set(userId, { mime, data, version }); return version; }
  async getAvatarBlob(userId: string) { return this.avatars.get(userId) ?? null; }
  async clearAvatarBlob(userId: string) { this.avatars.delete(userId); }

  async createDuel(d: Duel) { this.duels.set(d.id, structuredClone(d)); return d; }
  async getDuel(id: string) { const d = this.duels.get(id); return d ? structuredClone(d) : null; }
  async saveDuel(d: Duel) { this.duels.set(d.id, structuredClone(d)); }
  async listDuels(userId: string, limit: number) {
    return [...this.duels.values()].filter((d) => d.challengerId === userId || d.targetId === userId)
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)).slice(0, limit).map((d) => structuredClone(d));
  }
  async addPoints(e: NewLedgerEntry) {
    if (this.points.some((x) => x.key === e.key)) return null;
    const row: LedgerEntry = { ...e, id: randomUUID(), createdAt: new Date(this.clock()).toISOString() };
    this.points.push(row); return row;
  }
  async ledger(userId: string, limit: number) { return this.points.filter((e) => e.userId === userId).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)).slice(0, limit); }
  async ledgerSince(userId: string, kinds: LedgerKind[], sinceIso: string) {
    const t = Date.parse(sinceIso);
    return this.points.filter((e) => e.userId === userId && kinds.includes(e.kind) && Date.parse(e.createdAt) >= t).reduce((a, e) => a + e.amount, 0);
  }

  async saveSession(state: EngineState, visibility: 'public' | 'private') { this.sessions.set(state.id, { state: structuredClone(state), visibility }); }
  async loadActiveSessions() { return [...this.sessions.values()].filter((s) => s.state.phase !== 'SESSION_END'); }
  async appendEvents(sessionId: string, events: EngineEvent[]) { for (const e of events) this.events.push({ sessionId, e }); }
  async saveRound(sessionId: string, _round: Round, result: RoundResult) { this.results.push({ sessionId, result }); }
  async saveGeneration(_s: string, _n: number, _r: GenerationReport) { /* not retained in memory */ }
  async history(userId: string, limit: number) { return this.results.filter((r) => r.result.playerId === userId).map((r) => r.result).slice(-limit).reverse(); }
  async leaderboard(limit: number): Promise<LeaderRow[]> {
    const agg = new Map<string, LeaderRow>();
    for (const { result: r } of this.results) {
      const p = this.profiles.get(r.playerId);
      const row = agg.get(r.playerId) ?? { userId: r.playerId, handle: p?.handle ?? r.playerHandle, avatar: p?.avatar ?? DEFAULT_AVATAR, points: 0, completed: 0 };
      row.points += r.playerPoints; if (r.outcome === 'completed') row.completed++;
      agg.set(r.playerId, row);
    }
    for (const e of this.points) {
      const p = this.profiles.get(e.userId);
      const row = agg.get(e.userId) ?? { userId: e.userId, handle: p?.handle ?? '?', avatar: p?.avatar ?? DEFAULT_AVATAR, points: 0, completed: 0 };
      row.points += e.amount; agg.set(e.userId, row);
    }
    return [...agg.values()].sort((a, b) => b.points - a.points).slice(0, limit);
  }

  async createReport(r: { reporterId: string; targetUserId?: string; sessionId?: string; clipId?: string; kind: string; note: string }) {
    if (r.clipId) { const set = this.clipReports.get(r.clipId) ?? new Set<string>(); set.add(r.reporterId); this.clipReports.set(r.clipId, set); }
    const rep: Report = { id: randomUUID(), reporterId: r.reporterId, targetUserId: r.targetUserId ?? null, sessionId: r.sessionId ?? null, kind: r.kind, note: r.note, status: 'open', resolution: null, createdAt: new Date().toISOString() };
    this.reports.push(rep); return rep;
  }
  async listReports(status: 'open' | 'resolved') { return this.reports.filter((r) => r.status === status); }
  async resolveReport(id: string, _m: string, action: string, _note: string) {
    const r = this.reports.find((x) => x.id === id); if (!r) return null;
    r.status = 'resolved'; r.resolution = action; return r;
  }
  // ---- follows ----
  async addFollow(a: string, b: string) { const k = `${a}>${b}`; if (this.follows.has(k)) return false; this.follows.add(k); return true; }
  async removeFollow(a: string, b: string) { this.follows.delete(`${a}>${b}`); }
  async isFollowing(a: string, b: string) { return this.follows.has(`${a}>${b}`); }
  async followCounts(u: string) { let followers = 0, following = 0; for (const k of this.follows) { if (k.endsWith(`>${u}`)) followers++; if (k.startsWith(`${u}>`)) following++; } return { followers, following }; }
  async followerIds(u: string, limit: number) { return [...this.follows].filter((k) => k.endsWith(`>${u}`)).map((k) => k.split('>')[0]!).reverse().slice(0, limit); }
  async followingIds(u: string, limit: number) { return [...this.follows].filter((k) => k.startsWith(`${u}>`)).map((k) => k.split('>')[1]!).reverse().slice(0, limit); }

  // ---- chat ----
  async findConversation(a: string, b: string) { const [x, y] = pairOf(a, b); return [...this.conversations.values()].find((c) => c.userA === x && c.userB === y) ?? null; }
  async getConversation(id: string) { return this.conversations.get(id) ?? null; }
  async createConversation(a: string, b: string, initiatorId: string, status: Conversation['status']) {
    const [x, y] = pairOf(a, b); const now = new Date(this.clock()).toISOString();
    const c: Conversation = { id: randomUUID(), userA: x, userB: y, initiatorId, status, createdAt: now, updatedAt: now, lastReadA: null, lastReadB: null };
    this.conversations.set(c.id, c); return c;
  }
  async setConversationStatus(id: string, status: Conversation['status']) { const c = this.conversations.get(id); if (c) { c.status = status; c.updatedAt = new Date(this.clock()).toISOString(); } }
  async listConversations(u: string, limit: number) { return [...this.conversations.values()].filter((c) => c.userA === u || c.userB === u).sort((p, q) => q.updatedAt.localeCompare(p.updatedAt)).slice(0, limit); }
  async addMessage(conversationId: string, senderId: string, text: string) {
    const m: ChatMessage = { id: randomUUID(), conversationId, senderId, text, createdAt: new Date(this.clock()).toISOString() };
    this.messages.push(m); const c = this.conversations.get(conversationId); if (c) c.updatedAt = m.createdAt; return m;
  }
  async listMessages(conversationId: string, limit: number) { return this.messages.filter((m) => m.conversationId === conversationId).slice(-limit); }
  async lastMessage(conversationId: string) { const l = this.messages.filter((m) => m.conversationId === conversationId); return l[l.length - 1] ?? null; }
  async messageCountBy(conversationId: string, senderId: string) { return this.messages.filter((m) => m.conversationId === conversationId && m.senderId === senderId).length; }
  async markRead(conversationId: string, u: string) { const c = this.conversations.get(conversationId); if (!c) return; const now = new Date(this.clock() + 1).toISOString(); if (c.userA === u) c.lastReadA = now; else if (c.userB === u) c.lastReadB = now; }
  async unreadCount(conversationId: string, u: string) {
    const c = this.conversations.get(conversationId); if (!c) return 0;
    const since = (c.userA === u ? c.lastReadA : c.lastReadB) ?? '';
    return this.messages.filter((m) => m.conversationId === conversationId && m.senderId !== u && m.createdAt > since).length;
  }

  // ---- activity ----
  async addNotification(n: { userId: string; kind: NotificationKind; actorId: string; ref?: string | null }) {
    if (n.userId === n.actorId) return;
    if (this.notifications.some((x) => x.userId === n.userId && x.kind === n.kind && x.actorId === n.actorId && (x.ref ?? null) === (n.ref ?? null))) return;
    this.notifications.push({ id: randomUUID(), userId: n.userId, kind: n.kind, actorId: n.actorId, ref: n.ref ?? null, createdAt: new Date(this.clock()).toISOString(), readAt: null });
  }
  async listNotifications(u: string, limit: number) { return this.notifications.filter((n) => n.userId === u).reverse().slice(0, limit); }
  async markNotificationsRead(u: string) { const now = new Date(this.clock()).toISOString(); for (const n of this.notifications) if (n.userId === u && !n.readAt) n.readAt = now; }
  async unreadNotificationCount(u: string) { return this.notifications.filter((n) => n.userId === u && !n.readAt).length; }

  async addBlock(a: string, b: string) { this.blocks.add(`${a}>${b}`); }
  async removeBlock(a: string, b: string) { this.blocks.delete(`${a}>${b}`); }
  async blockedIds(u: string) { return [...this.blocks].filter((k) => k.startsWith(`${u}>`)).map((k) => k.split('>')[1]!); }
  async blockedEitherWay(a: string, b: string) { return this.blocks.has(`${a}>${b}`) || this.blocks.has(`${b}>${a}`); }
  async logModeration(a: unknown) { this.moderation.push(a); }

  async clipReporterCount(clipId: string) { return this.clipReports.get(clipId)?.size ?? 0; }

  async createClip(c: NewClip) {
    const clip: Clip = {
      id: randomUUID(), sessionId: c.sessionId ?? null, roundNo: c.roundNo ?? null, authorId: c.authorId, authorHandle: c.authorHandle,
      authorAvatar: c.authorAvatar, title: c.title, caption: c.caption ?? '', category: c.category, difficulty: c.difficulty, twist: c.twist ?? null,
      durationMs: c.durationMs, storagePath: c.storagePath, status: c.status ?? 'awaiting', likes: 0, views: 0,
      createdAt: new Date(this.clock()).toISOString(), publishedAt: c.status === 'published' ? new Date(this.clock()).toISOString() : null,
    };
    this.clips.set(clip.id, clip); return clip;
  }
  async getClip(id: string) { return this.clips.get(id) ?? null; }
  async publishClip(id: string, authorId: string, caption: string) {
    const c = this.clips.get(id);
    if (!c || c.authorId !== authorId || c.status !== 'awaiting') return null;
    c.status = 'published'; c.caption = caption.slice(0, 140); c.publishedAt = new Date(this.clock()).toISOString();
    return c;
  }
  async setClipStatus(id: string, status: ClipStatus) { const c = this.clips.get(id); if (c) c.status = status; }
  async deleteClip(id: string) { const c = this.clips.get(id) ?? null; this.clips.delete(id); return c; }
  async listFeed(q: FeedQuery): Promise<FeedRow[]> {
    const now = this.clock();
    const rows = [...this.clips.values()].filter((c) => c.status === 'published' && !q.blocked.includes(c.authorId) && (!q.onlyAuthors || q.onlyAuthors.includes(c.authorId)));
    const seen = (c: Clip) => this.seen.has(`${c.id}>${q.viewerId}`);
    const t = (c: Clip) => Date.parse(c.publishedAt ?? c.createdAt);
    rows.sort(q.sort === 'new'
      ? (a, b) => t(b) - t(a)
      : (a, b) => Number(seen(a)) - Number(seen(b)) || hotScore(b.likes, b.views, t(b), now) - hotScore(a.likes, a.views, t(a), now));
    return rows.slice(q.page * q.limit, q.page * q.limit + q.limit).map((c) => ({ ...c, liked: this.likes.has(`${c.id}>${q.viewerId}`) }));
  }
  async setLike(clipId: string, userId: string, on: boolean) {
    const c = this.clips.get(clipId); if (!c || c.status !== 'published') return null;
    const k = `${clipId}>${userId}`;
    if (on) this.likes.add(k); else this.likes.delete(k);
    c.likes = [...this.likes].filter((x) => x.startsWith(`${clipId}>`)).length;
    return { likes: c.likes, liked: on };
  }
  async recordView(clipId: string, userId: string) {
    const c = this.clips.get(clipId); const k = `${clipId}>${userId}`;
    if (c && !this.seen.has(k)) { this.seen.add(k); c.views++; }
  }
  async myClips(userId: string) { return [...this.clips.values()].filter((c) => c.authorId === userId && c.status !== 'removed'); }
  async clipsByStatus(status: ClipStatus) { return [...this.clips.values()].filter((c) => c.status === status); }
  async expireAwaiting(olderThanMs: number) {
    const cut = this.clock() - olderThanMs; const out: Clip[] = [];
    for (const c of this.clips.values()) if (c.status === 'awaiting' && Date.parse(c.createdAt) < cut) { out.push(c); this.clips.delete(c.id); }
    return out;
  }

  async userStats(userId: string): Promise<UserStats> {
    const mine = this.results.filter((r) => r.result.playerId === userId).map((r) => r.result);
    const clips = [...this.clips.values()].filter((c) => c.authorId === userId && c.status === 'published');
    return {
      rounds: mine.length, completed: mine.filter((r) => r.outcome === 'completed').length,
      points: mine.reduce((a, r) => a + r.playerPoints, 0) + this.points.filter((e) => e.userId === userId).reduce((a, e) => a + e.amount, 0),
      bestStreak: mine.reduce((a, r) => Math.max(a, r.streak), 0), clips: clips.length, likes: clips.reduce((a, c) => a + c.likes, 0),
      duels: [...this.duels.values()].filter((d) => d.targetId === userId && d.status === 'completed').length,
    };
  }
  async clipsByAuthor(authorId: string, limit: number) {
    return [...this.clips.values()].filter((c) => c.authorId === authorId && c.status === 'published')
      .sort((a, b) => Date.parse(b.publishedAt ?? b.createdAt) - Date.parse(a.publishedAt ?? a.createdAt)).slice(0, limit);
  }
}
