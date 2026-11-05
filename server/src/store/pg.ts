// PostgreSQL (Supabase) repository. Plain parameterised SQL through `pg`: no ORM, every query is visible and reviewable.
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { sanitizeBoundaries } from '../policy/types.ts';
import type { EngineEvent, EngineState, Round, RoundResult } from '../engine/index.ts';
import type { GenerationReport } from '../director/director.ts';
import { pairOf } from './types.ts';
import type { ChatMessage, Conversation, Notification, NotificationKind, UserStats, Clip, ClipStatus, Duel, DuelStatus, FeedQuery, FeedRow, HandleHit, LeaderRow, LedgerEntry, LedgerKind, NewClip, NewLedgerEntry, Profile, Report, Repo, UserRole } from './types.ts';

type Row = Record<string, any>;

const isoOrNull = (v: unknown): string | null => (v ? new Date(v as string).toISOString() : null);
const toConversation = (r: Row): Conversation => ({ id: r.id, userA: r.user_a, userB: r.user_b, initiatorId: r.initiator_id, status: r.status, createdAt: isoOrNull(r.created_at)!, updatedAt: isoOrNull(r.updated_at)!, lastReadA: isoOrNull(r.last_read_a), lastReadB: isoOrNull(r.last_read_b) });
const toMessage = (r: Row): ChatMessage => ({ id: r.id, conversationId: r.conversation_id, senderId: r.sender_id, text: r.text, createdAt: isoOrNull(r.created_at)! });
const toNotification = (r: Row): Notification => ({ id: r.id, userId: r.user_id, kind: r.kind, actorId: r.actor_id, ref: r.ref ?? null, createdAt: isoOrNull(r.created_at)!, readAt: isoOrNull(r.read_at) });

const toProfile = (r: Row): Profile => ({
  id: r.id, handle: r.handle, avatar: r.avatar, birthDate: r.birth_date ? String(r.birth_date).slice(0, 10) : null,
  ageVerifiedAt: r.age_verified_at ? new Date(r.age_verified_at).toISOString() : null, role: r.role,
  boundaries: sanitizeBoundaries(r.boundaries), bio: r.bio ?? '', accent: r.accent ?? 'neon', suspendedUntil: r.suspended_until ? new Date(r.suspended_until).toISOString() : null,
  createdAt: new Date(r.created_at).toISOString(),
});
const toReport = (r: Row): Report => ({
  id: r.id, reporterId: r.reporter_id, targetUserId: r.target_user_id, sessionId: r.session_id, kind: r.kind, note: r.note,
  status: r.status, resolution: r.resolution, createdAt: new Date(r.created_at).toISOString(),
});

const toClip = (r: Row): Clip => ({
  id: r.id, sessionId: r.session_id, roundNo: r.round_no, authorId: r.author_id, authorHandle: r.author_handle, authorAvatar: r.author_avatar,
  title: r.title, caption: r.caption, category: r.category, difficulty: r.difficulty, twist: r.twist, durationMs: r.duration_ms,
  storagePath: r.storage_path, status: r.status, likes: r.likes, views: r.views, createdAt: new Date(r.created_at).toISOString(),
  publishedAt: r.published_at ? new Date(r.published_at).toISOString() : null,
});

const iso = (v: unknown) => new Date(v as string).toISOString();
const toDuel = (r: Row): Duel => ({
  id: r.id, challengerId: r.challenger_id, challengerHandle: r.challenger_handle, challengerAvatar: r.challenger_avatar,
  targetId: r.target_id, targetHandle: r.target_handle, targetAvatar: r.target_avatar,
  title: r.title, objective: r.objective, category: r.category, difficulty: r.difficulty, durationSeconds: r.duration_seconds,
  criteria: Array.isArray(r.criteria) ? r.criteria : [], origin: r.origin, status: r.status as DuelStatus, note: r.note, proofClipId: r.proof_clip_id ?? null,
  reward: r.reward, rewarded: r.rewarded, createdAt: iso(r.created_at), updatedAt: iso(r.updated_at), expiresAt: iso(r.expires_at),
  resolvedAt: r.resolved_at ? iso(r.resolved_at) : null,
});
const toLedger = (r: Row): LedgerEntry => ({ id: r.id, userId: r.user_id, amount: r.amount, kind: r.kind as LedgerKind, ref: r.ref, key: r.key, note: r.note, createdAt: iso(r.created_at) });

export class PgRepo implements Repo {
  pool: InstanceType<typeof pg.Pool>;

  constructor(databaseUrl: string) {
    // Supabase requires TLS; the pooler URL (port 6543) is recommended for servers.
    this.pool = new pg.Pool({ connectionString: databaseUrl, max: 10, ssl: databaseUrl.includes('localhost') || databaseUrl.includes('127.0.0.1') ? undefined : { rejectUnauthorized: false } });
  }

  private async q(text: string, params: unknown[] = []): Promise<Row[]> { return (await this.pool.query(text, params)).rows; }

  async getProfile(id: string) { const r = await this.q('select * from public.profiles where id = $1', [id]); return r[0] ? toProfile(r[0]) : null; }
  async ensureProfile(id: string) {
    await this.q('insert into public.profiles (id) values ($1) on conflict do nothing', [id]);
    return (await this.getProfile(id))!;
  }
  async updateProfile(id: string, patch: Partial<Pick<Profile, 'handle' | 'avatar' | 'boundaries' | 'bio' | 'accent'>>) {
    try {
      await this.q(
        `update public.profiles set handle = coalesce($2, handle), avatar = coalesce($3, avatar), boundaries = coalesce($4::jsonb, boundaries), bio = coalesce($5, bio), accent = coalesce($6, accent), updated_at = now() where id = $1`,
        [id, patch.handle ?? null, patch.avatar ?? null, patch.boundaries ? JSON.stringify(sanitizeBoundaries(patch.boundaries)) : null, patch.bio ?? null, patch.accent ?? null],
      );
    } catch (e) {
      if ((e as { code?: string }).code === '23505') throw new Error('handle_taken');
      throw e;
    }
    return (await this.getProfile(id))!;
  }
  async setAge(id: string, birthDate: string, verified = true) {
    await this.q('update public.profiles set birth_date = $2, age_verified_at = case when $3::boolean then now() else null end, updated_at = now() where id = $1', [id, birthDate, verified]);
    return (await this.getProfile(id))!;
  }
  async setRole(id: string, role: UserRole) { await this.q('update public.profiles set role = $2 where id = $1', [id, role]); }
  async suspend(id: string, until: string | null) { await this.q('update public.profiles set suspended_until = $2 where id = $1', [id, until]); }
  async deleteUser(id: string) { await this.q('delete from public.profiles where id = $1', [id]); }   // avatars, duels and ledger cascade
  async searchHandles(prefix: string, limit: number, excludeIds: string[]): Promise<HandleHit[]> {
    const safe = prefix.toLowerCase().replace(/[^a-z0-9_]/g, '');
    const rows = await this.q(
      `select id, handle, avatar from public.profiles where handle like $1 and age_verified_at is not null and not (id = any($2::uuid[]))
       order by char_length(handle), handle limit $3`, [`${safe}%`, excludeIds.filter((x) => /^[0-9a-f-]{36}$/i.test(x)), limit]);
    return rows.map((r) => ({ id: r.id, handle: r.handle, avatar: r.avatar }));
  }

  async setAvatarBlob(userId: string, mime: string, data: Buffer) {
    const r = await this.q(
      `insert into public.avatars (user_id, mime, data, updated_at) values ($1,$2,$3,now())
       on conflict (user_id) do update set mime = excluded.mime, data = excluded.data, updated_at = now() returning (extract(epoch from updated_at) * 1000)::bigint as v`, [userId, mime, data]);
    return Number(r[0]!.v);
  }
  async getAvatarBlob(userId: string) {
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return null;
    const r = await this.q('select mime, data, (extract(epoch from updated_at) * 1000)::bigint as v from public.avatars where user_id = $1', [userId]);
    return r[0] ? { mime: r[0].mime as string, data: r[0].data as Buffer, version: Number(r[0].v) } : null;
  }
  async clearAvatarBlob(userId: string) { await this.q('delete from public.avatars where user_id = $1', [userId]); }

  async createDuel(d: Duel) {
    const r = await this.q(
      `insert into public.duels (id, challenger_id, challenger_handle, challenger_avatar, target_id, target_handle, target_avatar, title, objective, category, difficulty,
         duration_seconds, criteria, origin, status, note, proof_clip_id, reward, rewarded, expires_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,$14,$15,$16,$17,$18,$19,$20) returning *`,
      [d.id, d.challengerId, d.challengerHandle, d.challengerAvatar, d.targetId, d.targetHandle, d.targetAvatar, d.title, d.objective, d.category, d.difficulty,
        d.durationSeconds, JSON.stringify(d.criteria), d.origin, d.status, d.note, d.proofClipId, d.reward, d.rewarded, d.expiresAt]);
    return toDuel(r[0]!);
  }
  async getDuel(id: string) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
    const r = await this.q('select * from public.duels where id = $1', [id]); return r[0] ? toDuel(r[0]) : null;
  }
  async saveDuel(d: Duel) {
    await this.q(`update public.duels set status = $2, note = $3, proof_clip_id = $4, rewarded = $5, resolved_at = $6, expires_at = $7, updated_at = now() where id = $1`,
      [d.id, d.status, d.note, d.proofClipId, d.rewarded, d.resolvedAt, d.expiresAt]);
  }
  async listDuels(userId: string, limit: number) {
    return (await this.q('select * from public.duels where challenger_id = $1 or target_id = $1 order by created_at desc limit $2', [userId, limit])).map(toDuel);
  }
  async addPoints(e: NewLedgerEntry) {
    const r = await this.q(
      `insert into public.points_ledger (user_id, amount, kind, ref, key, note) values ($1,$2,$3,$4,$5,$6) on conflict (key) do nothing returning *`,
      [e.userId, e.amount, e.kind, e.ref, e.key, e.note]);
    return r[0] ? toLedger(r[0]) : null;
  }
  async ledger(userId: string, limit: number) { return (await this.q('select * from public.points_ledger where user_id = $1 order by created_at desc limit $2', [userId, limit])).map(toLedger); }
  async ledgerSince(userId: string, kinds: LedgerKind[], sinceIso: string) {
    const r = await this.q('select coalesce(sum(amount), 0)::int as n from public.points_ledger where user_id = $1 and kind = any($2::text[]) and created_at >= $3', [userId, kinds, sinceIso]);
    return Number(r[0]!.n);
  }

  async saveSession(s: EngineState, visibility: 'public' | 'private') {
    await this.q(
      `insert into public.sessions (id, code, title, host_id, visibility, status, phase, state, ended_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8::jsonb, case when $6 = 'ended' then now() end)
       on conflict (id) do update set phase = excluded.phase, status = excluded.status, state = excluded.state, title = excluded.title,
         updated_at = now(), ended_at = coalesce(public.sessions.ended_at, excluded.ended_at)`,
      [s.id, s.code, s.config.title, s.config.hostId, visibility, s.phase === 'SESSION_END' ? 'ended' : 'active', s.phase, JSON.stringify(s)],
    );
  }
  async loadActiveSessions() {
    const rows = await this.q(`select state, visibility from public.sessions where status = 'active'`);
    return rows.map((r) => ({ state: r.state as EngineState, visibility: r.visibility as 'public' | 'private' }));
  }
  async appendEvents(sessionId: string, events: EngineEvent[]) {
    if (!events.length) return;
    const values: unknown[] = []; const tuples: string[] = [];
    events.forEach((e, i) => { tuples.push(`($${i * 4 + 1},$${i * 4 + 2},$${i * 4 + 3},$${i * 4 + 4}::jsonb)`); values.push(sessionId, e.rev, e.type, JSON.stringify(e.data)); });
    await this.q(`insert into public.game_events (session_id, rev, type, data) values ${tuples.join(',')}`, values);
  }
  async saveRound(sessionId: string, round: Round, result: RoundResult) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const challenge = round.chosenIdx !== null ? round.options[round.chosenIdx] ?? null : null;
      const ins = await client.query(
        `insert into public.rounds (session_id, round_no, player_id, challenge, options, tally, outcome, judged, player_points, result)
         values ($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7,$8,$9,$10::jsonb)
         on conflict (session_id, round_no) do nothing returning id`,
        [sessionId, round.n, result.playerId || null, JSON.stringify(challenge), JSON.stringify(round.options), round.finalTally, result.outcome, result.judged, result.playerPoints, JSON.stringify(result)],
      );
      const roundId = ins.rows[0]?.id;
      if (roundId) {
        const ballots: [string, string, number][] = [];
        for (const [u, c] of Object.entries(round.votes)) ballots.push([u, 'challenge', c]);
        for (const [u, c] of Object.entries(round.twist?.votes ?? {})) ballots.push([u, 'twist', c]);
        for (const [u, v] of Object.entries(round.verdicts)) ballots.push([u, 'verdict', v ? 1 : 0]);
        for (const [u, kind, choice] of ballots) {
          // Bots and users who deleted their account have no profile row; skip those ballots instead of failing the round.
          await client.query(`insert into public.votes (round_id, user_id, kind, choice) select $1,$2,$3,$4 where exists (select 1 from public.profiles where id = $2) on conflict do nothing`, [roundId, u, kind, choice]);
        }
      }
      await client.query('commit');
    } catch (e) { await client.query('rollback'); throw e; } finally { client.release(); }
  }
  async saveGeneration(sessionId: string, roundNo: number, report: GenerationReport) {
    await this.q('insert into public.ai_generations (session_id, round_no, report) values ($1,$2,$3::jsonb)', [sessionId, roundNo, JSON.stringify(report)]);
  }
  async history(userId: string, limit: number) {
    const rows = await this.q('select result from public.rounds where player_id = $1 order by created_at desc limit $2', [userId, limit]);
    return rows.map((r) => r.result as RoundResult);
  }
  async leaderboard(limit: number): Promise<LeaderRow[]> {
    const rows = await this.q(
      `with pts as (
         select r.player_id as uid, r.player_points as pts, (r.outcome = 'completed')::int as done, r.created_at from public.rounds r where r.player_id is not null
         union all
         select l.user_id, l.amount, 0, l.created_at from public.points_ledger l
       )
       select p.id as user_id, p.handle, p.avatar, sum(pts.pts)::int as points, sum(pts.done)::int as completed
         from pts join public.profiles p on p.id = pts.uid
        where pts.created_at > now() - interval '30 days' and p.handle is not null
        group by p.id order by points desc limit $1`, [limit]);
    return rows.map((r) => ({ userId: r.user_id, handle: r.handle, avatar: r.avatar, points: r.points, completed: r.completed }));
  }

  async createReport(r: { reporterId: string; targetUserId?: string; sessionId?: string; clipId?: string; kind: string; note: string }) {
    const rows = await this.q(
      `insert into public.reports (id, reporter_id, target_user_id, session_id, clip_id, kind, note) values ($1,$2,$3,$4,$5,$6,$7) returning *`,
      [randomUUID(), r.reporterId, r.targetUserId ?? null, r.sessionId ?? null, r.clipId ?? null, r.kind, r.note]);
    return toReport(rows[0]!);
  }
  async listReports(status: 'open' | 'resolved') { return (await this.q('select * from public.reports where status = $1 order by created_at asc limit 200', [status])).map(toReport); }
  async resolveReport(id: string, moderatorId: string, action: string, _note: string) {
    const rows = await this.q(`update public.reports set status = 'resolved', resolution = $3, resolved_by = $2, resolved_at = now() where id = $1 and status = 'open' returning *`, [id, moderatorId, action]);
    return rows[0] ? toReport(rows[0]) : null;
  }
  // ---- follows ----
  async addFollow(a: string, b: string) { return (await this.q('insert into public.follows (follower_id, followee_id) values ($1,$2) on conflict do nothing returning 1', [a, b])).length > 0; }
  async removeFollow(a: string, b: string) { await this.q('delete from public.follows where follower_id = $1 and followee_id = $2', [a, b]); }
  async isFollowing(a: string, b: string) { return (await this.q('select 1 from public.follows where follower_id = $1 and followee_id = $2', [a, b])).length > 0; }
  async followCounts(u: string) {
    const r = (await this.q('select (select count(*) from public.follows where followee_id = $1)::int as followers, (select count(*) from public.follows where follower_id = $1)::int as following', [u]))[0]!;
    return { followers: Number(r.followers), following: Number(r.following) };
  }
  async followerIds(u: string, limit: number) { return (await this.q('select follower_id from public.follows where followee_id = $1 order by created_at desc limit $2', [u, limit])).map((r) => r.follower_id as string); }
  async followingIds(u: string, limit: number) { return (await this.q('select followee_id from public.follows where follower_id = $1 order by created_at desc limit $2', [u, limit])).map((r) => r.followee_id as string); }

  // ---- chat ----
  async findConversation(a: string, b: string) { const [x, y] = pairOf(a, b); const r = await this.q('select * from public.conversations where user_a = $1 and user_b = $2', [x, y]); return r[0] ? toConversation(r[0]) : null; }
  async getConversation(id: string) { const r = await this.q('select * from public.conversations where id = $1', [id]); return r[0] ? toConversation(r[0]) : null; }
  async createConversation(a: string, b: string, initiatorId: string, status: Conversation['status']) {
    const [x, y] = pairOf(a, b);
    return toConversation((await this.q('insert into public.conversations (user_a, user_b, initiator_id, status) values ($1,$2,$3,$4) returning *', [x, y, initiatorId, status]))[0]!);
  }
  async setConversationStatus(id: string, status: Conversation['status']) { await this.q('update public.conversations set status = $2, updated_at = now() where id = $1', [id, status]); }
  async listConversations(u: string, limit: number) { return (await this.q('select * from public.conversations where user_a = $1 or user_b = $1 order by updated_at desc limit $2', [u, limit])).map(toConversation); }
  async addMessage(conversationId: string, senderId: string, text: string) {
    const m = toMessage((await this.q('insert into public.messages (conversation_id, sender_id, text) values ($1,$2,$3) returning *', [conversationId, senderId, text]))[0]!);
    await this.q('update public.conversations set updated_at = $2 where id = $1', [conversationId, m.createdAt]);
    return m;
  }
  async listMessages(conversationId: string, limit: number) { return (await this.q('select * from (select * from public.messages where conversation_id = $1 order by created_at desc limit $2) t order by created_at asc', [conversationId, limit])).map(toMessage); }
  async lastMessage(conversationId: string) { const r = await this.q('select * from public.messages where conversation_id = $1 order by created_at desc limit 1', [conversationId]); return r[0] ? toMessage(r[0]) : null; }
  async messageCountBy(conversationId: string, senderId: string) { return Number((await this.q('select count(*)::int as n from public.messages where conversation_id = $1 and sender_id = $2', [conversationId, senderId]))[0]!.n); }
  async markRead(conversationId: string, u: string) {
    await this.q('update public.conversations set last_read_a = case when user_a = $2 then now() else last_read_a end, last_read_b = case when user_b = $2 then now() else last_read_b end where id = $1', [conversationId, u]);
  }
  async unreadCount(conversationId: string, u: string) {
    const r = await this.q(`select count(*)::int as n from public.messages m join public.conversations c on c.id = m.conversation_id
                              where m.conversation_id = $1 and m.sender_id <> $2
                                and m.created_at > coalesce(case when c.user_a = $2 then c.last_read_a else c.last_read_b end, 'epoch'::timestamptz)`, [conversationId, u]);
    return Number(r[0]!.n);
  }

  // ---- activity ----
  async addNotification(n: { userId: string; kind: NotificationKind; actorId: string; ref?: string | null }) {
    if (n.userId === n.actorId) return;
    await this.q('insert into public.notifications (user_id, kind, actor_id, ref) values ($1,$2,$3,$4) on conflict do nothing', [n.userId, n.kind, n.actorId, n.ref ?? '']);
  }
  async listNotifications(u: string, limit: number) { return (await this.q('select * from public.notifications where user_id = $1 order by created_at desc limit $2', [u, limit])).map((r) => toNotification({ ...r, ref: r.ref || null })); }
  async markNotificationsRead(u: string) { await this.q('update public.notifications set read_at = now() where user_id = $1 and read_at is null', [u]); }
  async unreadNotificationCount(u: string) { return Number((await this.q('select count(*)::int as n from public.notifications where user_id = $1 and read_at is null', [u]))[0]!.n); }

  async addBlock(a: string, b: string) { await this.q('insert into public.blocks (blocker_id, blocked_id) values ($1,$2) on conflict do nothing', [a, b]); }
  async removeBlock(a: string, b: string) { await this.q('delete from public.blocks where blocker_id = $1 and blocked_id = $2', [a, b]); }
  async blockedIds(u: string) { return (await this.q('select blocked_id from public.blocks where blocker_id = $1', [u])).map((r) => r.blocked_id as string); }
  async blockedEitherWay(a: string, b: string) {
    return (await this.q('select 1 from public.blocks where (blocker_id = $1 and blocked_id = $2) or (blocker_id = $2 and blocked_id = $1) limit 1', [a, b])).length > 0;
  }
  async logModeration(a: { moderatorId: string; action: string; targetUserId?: string; sessionId?: string; reportId?: string; note?: string }) {
    await this.q('insert into public.moderation_actions (moderator_id, action, target_user_id, session_id, report_id, note) values ($1,$2,$3,$4,$5,$6)',
      [a.moderatorId, a.action, a.targetUserId ?? null, a.sessionId ?? null, a.reportId ?? null, a.note ?? '']);
  }

  async clipReporterCount(clipId: string) {
    return Number((await this.q('select count(distinct reporter_id)::int as n from public.reports where clip_id = $1', [clipId]))[0]?.n ?? 0);
  }

  async createClip(c: NewClip) {
    const rows = await this.q(
      `insert into public.clips (session_id, round_no, author_id, author_handle, author_avatar, title, caption, category, difficulty, twist, duration_ms, storage_path, status)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) returning *`,
      [c.sessionId ?? null, c.roundNo ?? null, c.authorId, c.authorHandle, c.authorAvatar, c.title, c.caption ?? '', c.category, c.difficulty, c.twist ?? null, c.durationMs, c.storagePath, c.status ?? 'awaiting']);
    return toClip(rows[0]!);
  }
  async getClip(id: string) { const r = await this.q('select * from public.clips where id = $1', [id]); return r[0] ? toClip(r[0]) : null; }
  async publishClip(id: string, authorId: string, caption: string) {
    const r = await this.q(`update public.clips set status = 'published', caption = $3, published_at = now() where id = $1 and author_id = $2 and status = 'awaiting' returning *`, [id, authorId, caption.slice(0, 140)]);
    return r[0] ? toClip(r[0]) : null;
  }
  async setClipStatus(id: string, status: ClipStatus) { await this.q('update public.clips set status = $2 where id = $1', [id, status]); }
  async deleteClip(id: string) { const r = await this.q('delete from public.clips where id = $1 returning *', [id]); return r[0] ? toClip(r[0]) : null; }
  async listFeed(q: FeedQuery): Promise<FeedRow[]> {
    const order = q.sort === 'new'
      ? 'c.published_at desc'
      : `(v.user_id is not null) asc, (c.likes * 3 + c.views * 0.2 + 1) / power(extract(epoch from now() - c.published_at) / 3600 + 2, 1.4) desc`;
    const rows = await this.q(
      `select c.*, (l.user_id is not null) as liked
         from public.clips c
         left join public.clip_likes l on l.clip_id = c.id and l.user_id = $1
         left join public.clip_views v on v.clip_id = c.id and v.user_id = $1
        where c.status = 'published' and not (c.author_id = any($2::uuid[])) and ($5::uuid[] is null or c.author_id = any($5::uuid[]))
        order by ${order} limit $3 offset $4`,
      [q.viewerId, q.blocked, q.limit, q.page * q.limit, q.onlyAuthors ?? null]);
    return rows.map((r) => ({ ...toClip(r), liked: !!r.liked }));
  }
  async setLike(clipId: string, userId: string, on: boolean) {
    const ok = await this.q(`select 1 from public.clips where id = $1 and status = 'published'`, [clipId]);
    if (!ok.length) return null;
    if (on) await this.q('insert into public.clip_likes (clip_id, user_id) values ($1,$2) on conflict do nothing', [clipId, userId]);
    else await this.q('delete from public.clip_likes where clip_id = $1 and user_id = $2', [clipId, userId]);
    const r = await this.q('update public.clips set likes = (select count(*) from public.clip_likes where clip_id = $1) where id = $1 returning likes', [clipId]);
    return { likes: r[0]!.likes as number, liked: on };
  }
  async recordView(clipId: string, userId: string) {
    const r = await this.q('insert into public.clip_views (clip_id, user_id) values ($1,$2) on conflict do nothing returning 1', [clipId, userId]);
    if (r.length) await this.q('update public.clips set views = views + 1 where id = $1', [clipId]);
  }
  async myClips(userId: string) { return (await this.q(`select * from public.clips where author_id = $1 and status <> 'removed' order by created_at desc limit 100`, [userId])).map(toClip); }
  async clipsByStatus(status: ClipStatus) { return (await this.q('select * from public.clips where status = $1 order by created_at asc limit 200', [status])).map(toClip); }
  async expireAwaiting(olderThanMs: number) {
    return (await this.q(`delete from public.clips where status = 'awaiting' and created_at < now() - ($1 || ' milliseconds')::interval returning *`, [String(olderThanMs)])).map(toClip);
  }

  async userStats(userId: string): Promise<UserStats> {
    const r = (await this.q(
      `select (select count(*)::int from public.rounds where player_id = $1) as rounds,
              (select count(*)::int from public.rounds where player_id = $1 and outcome = 'completed') as completed,
              ((select coalesce(sum(player_points), 0) from public.rounds where player_id = $1) + (select coalesce(sum(amount), 0) from public.points_ledger where user_id = $1))::int as points,
              (select count(*)::int from public.duels where target_id = $1 and status = 'completed') as duels,
              (select coalesce(max((result->>'streak')::int), 0) from public.rounds where player_id = $1) as best_streak,
              (select count(*)::int from public.clips where author_id = $1 and status = 'published') as clips,
              (select coalesce(sum(likes), 0)::int from public.clips where author_id = $1 and status = 'published') as likes`, [userId]))[0]!;
    return { rounds: r.rounds, completed: r.completed, points: r.points, bestStreak: r.best_streak, clips: r.clips, likes: r.likes, duels: r.duels };
  }
  async clipsByAuthor(authorId: string, limit: number) {
    return (await this.q(`select * from public.clips where author_id = $1 and status = 'published' order by published_at desc limit $2`, [authorId, limit])).map(toClip);
  }
}
