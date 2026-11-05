// REST API (Express). Authorization is enforced here and in the engine, never in the client.
// Full contract: docs/api.md
import { fileURLToPath } from 'node:url';
import express, { type Express, type NextFunction, type Request, type RequestHandler, type Response } from 'express';
import { cleanText } from '../policy/parse.ts';
import { CATEGORIES, TEEN_FLOOR, sanitizeBoundaries } from '../policy/types.ts';
import { MIN_AGE, bandForAge, bandOf, sameBand } from '../profile/age.ts';
import type { SessionManager } from '../realtime/manager.ts';
import type { Profile, Repo } from '../store/types.ts';
import type { Config } from '../util/config.ts';
import { AVATARS, DEFAULT_AVATAR, HANDLE_RE, ageFrom, customAvatarPath, isCustomAvatar } from '../util/ids.ts';
import { SocialError, SocialService, duelView } from '../social/service.ts';
import { GraphService } from '../social/graph.ts';
import { log } from '../util/log.ts';
import { RateLimiter } from '../util/ratelimit.ts';
import type { Storage } from '../media/storage.ts';
import type { Clip, FeedRow } from '../store/types.ts';
import { badgesFor, ACCENTS } from '../profile/badges.ts';
import { Cipher, CipherError } from '../cipher/service.ts';
import type { Verifier } from './auth.ts';

export interface AppDeps { cfg: Config; repo: Repo; manager: SessionManager; verify: Verifier; storage: Storage | null; cipher: Cipher; social?: SocialService }

class HttpError extends Error {
  status: number; code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
const bad = (code: string, message: string) => new HttpError(400, code, message);

const wrap = (fn: (req: Request, res: Response) => Promise<unknown>): RequestHandler => (req, res, next) => { fn(req, res).catch(next); };
const me = (res: Response): Profile => res.locals.profile as Profile;

/** What the app is told about its own account. `band` is derived from the date of birth on every request; the teen floor is sent so the app can show it. */
const selfView = (p: Profile) => {
  const band = bandOf(p);
  return { ...p, band, teenFloor: band === 'teen' ? TEEN_FLOOR : null };
};

const REPORT_KINDS = ['unsafe_challenge', 'harassment', 'underage', 'sexual_content', 'inappropriate_avatar', 'spam', 'other'];

/** Detects the real image type from the first bytes, so a client cannot upload anything else under an image content type. */
function sniffImage(b: Buffer): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (b.length > 12 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 12 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (b.length > 12 && b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
  return null;
}
const MAX_AVATAR_BYTES = 500 * 1024;

export function createApp(d: AppDeps): Express {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  // Demo videos and their poster frames (server/public/demo). Public and cacheable, like the avatars. Development only: DEMO_CLIPS is refused in production.
  if (d.cfg.clips.demo) {
    app.use('/demo', express.static(fileURLToPath(new URL('../../public/demo', import.meta.url)), {
      index: false, maxAge: '1h',
      setHeaders: (res) => { res.setHeader('Access-Control-Allow-Origin', d.cfg.corsOrigin); res.setHeader('X-Content-Type-Options', 'nosniff'); },
    }));
  }
  const json16 = express.json({ limit: '16kb' });
  app.use((req, res, next) => (req.path === '/v1/me/avatar' ? next() : json16(req, res, next)));   // the avatar route has its own, larger limit
  const social = d.social ?? new SocialService({ repo: d.repo });
  const graph = new GraphService(d.repo);
  const socialErr = (e: unknown): never => { if (e instanceof SocialError) throw new HttpError(e.status, e.code, e.message); throw e; };

  app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', d.cfg.corsOrigin);
    res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'OPTIONS') { res.status(204).end(); return; }
    next();
  });

  const ipLimit = new RateLimiter(60, 2);
  app.use((req, _res, next) => { if (!d.cfg.devAuth && !ipLimit.take(req.ip ?? 'x')) next(new HttpError(429, 'rate_limited', 'Too many requests')); else next(); });

  app.get('/health', (_req, res) => { res.json({ ok: true, sessions: d.manager.listAll().length }); });

  // ---- auth ---------------------------------------------------------------------------------------------------

  const authenticate = async (req: Request, res: Response): Promise<void> => {
    const h = req.header('authorization') ?? '';
    if (!h.startsWith('Bearer ')) throw new HttpError(401, 'unauthorized', 'Missing token');
    let user;
    try { user = await d.verify(h.slice(7)); } catch { throw new HttpError(401, 'unauthorized', 'Invalid token'); }
    let profile = await d.repo.ensureProfile(user.id);
    if (user.handleHint && !profile.handle) profile = await d.repo.updateProfile(user.id, { handle: user.handleHint }).catch(() => profile);
    if (profile.suspendedUntil && new Date(profile.suspendedUntil) > new Date()) throw new HttpError(403, 'suspended', 'This account is suspended');
    res.locals.profile = profile;
  };
  const needAuth: RequestHandler = (req, res, next) => { authenticate(req, res).then(() => next(), next); };

  const needMember: RequestHandler = (_req, res, next) => {
    const p = me(res);
    if (!p.ageVerifiedAt && p.role === 'user') return next(new HttpError(403, 'age_required', `DAREWIRE is for people aged ${MIN_AGE} and over`));
    if (!p.handle) return next(new HttpError(403, 'profile_incomplete', 'Choose a handle first'));
    next();
  };
  const needMod: RequestHandler = (_req, res, next) => { me(res).role === 'user' ? next(new HttpError(403, 'forbidden', 'Moderators only')) : next(); };

  // ---- profile ------------------------------------------------------------------------------------------------

  app.get('/v1/me', needAuth, wrap(async (_req, res) => {
    const p = me(res);
    res.json({ profile: selfView(p), needs: { age: !p.ageVerifiedAt, handle: !p.handle } });
  }));

  app.put('/v1/me', needAuth, wrap(async (req, res) => {
    const b = req.body ?? {};
    const patch: { handle?: string; avatar?: string; bio?: string; accent?: string; boundaries?: ReturnType<typeof sanitizeBoundaries> } = {};
    if (b.bio !== undefined) {
      const bio = cleanText(String(b.bio)).slice(0, 120);
      if (/https?:|www\.|@/i.test(bio)) throw bad('bad_bio', 'Bios cannot contain links or handles');
      patch.bio = bio;
    }
    if (b.accent !== undefined) {
      if (!(ACCENTS as readonly string[]).includes(b.accent)) throw bad('bad_accent', 'Unknown accent');
      patch.accent = b.accent;
    }
    if (b.handle !== undefined) {
      const h = String(b.handle).trim().toLowerCase();
      if (!HANDLE_RE.test(h)) throw bad('bad_handle', 'Handles are 3-20 characters: a-z, 0-9 and _');
      patch.handle = h;
    }
    if (b.avatar !== undefined) {
      // Built-in avatars only. A custom photo can only be set through PUT /v1/me/avatar, which stores the bytes first.
      if (!AVATARS.includes(String(b.avatar))) throw bad('bad_avatar', 'Unknown avatar');
      patch.avatar = String(b.avatar);
    }
    if (b.boundaries !== undefined) {
      const bd = sanitizeBoundaries(b.boundaries);
      if (CATEGORIES.length - bd.excludedCategories.length < 2) throw bad('too_restrictive', 'Leave at least two challenge categories enabled');
      patch.boundaries = bd;
    }
    try { res.json({ profile: selfView(await d.repo.updateProfile(me(res).id, patch)) }); }
    catch (e) { if (e instanceof Error && e.message === 'handle_taken') throw new HttpError(409, 'handle_taken', 'That handle is taken'); throw e; }
  }));

  // ---- custom avatar (picked from the phone's gallery) --------------------------------------------------------

  const avatarLimit = new RateLimiter(5, 5 / 600);
  app.put('/v1/me/avatar', express.json({ limit: '900kb' }), needAuth, wrap(async (req, res) => {
    const p = me(res);
    if (!p.ageVerifiedAt && p.role === 'user') throw new HttpError(403, 'age_required', `DAREWIRE is for people aged ${MIN_AGE} and over`);   // handle may not exist yet: this runs during sign-up
    if (!avatarLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'You are changing your photo too quickly');
    const b64 = typeof req.body?.data === 'string' ? req.body.data : '';
    if (!b64 || b64.length > 700_000) throw bad('bad_image', 'Choose a smaller photo');
    const bytes = Buffer.from(b64, 'base64');
    if (bytes.length > MAX_AVATAR_BYTES) throw bad('bad_image', 'That photo is too large (500 KB max)');
    const mime = sniffImage(bytes);
    if (!mime) throw bad('bad_image', 'Use a JPEG, PNG or WebP photo');
    const version = await d.repo.setAvatarBlob(p.id, mime, bytes);
    res.json({ profile: selfView(await d.repo.updateProfile(p.id, { avatar: customAvatarPath(p.id, version) })) });
  }));

  app.delete('/v1/me/avatar', needAuth, wrap(async (_req, res) => {
    await d.repo.clearAvatarBlob(me(res).id);
    res.json({ profile: selfView(await d.repo.updateProfile(me(res).id, { avatar: DEFAULT_AVATAR })) });
  }));

  // Public on purpose: Image.network cannot send our bearer token. The URL carries a version so it caches safely.
  app.get('/v1/avatars/:id', wrap(async (req, res) => {
    const blob = await d.repo.getAvatarBlob(String(req.params.id).slice(0, 64));
    if (!blob) throw new HttpError(404, 'not_found', 'No avatar');
    res.setHeader('Content-Type', blob.mime);
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");
    res.send(blob.data);
  }));

  app.post('/v1/mod/users/:id/reset-avatar', needAuth, needMod, wrap(async (req, res) => {
    const id = String(req.params.id).slice(0, 64);
    if (!(await d.repo.getProfile(id))) throw new HttpError(404, 'not_found', 'User not found');
    await d.repo.clearAvatarBlob(id);
    await d.repo.updateProfile(id, { avatar: DEFAULT_AVATAR });
    await d.repo.logModeration({ moderatorId: me(res).id, action: 'reset_avatar', targetUserId: id });
    res.status(204).end();
  }));

  // ---- points, daily quests, duels -------------------------------------------------------------------------------

  app.get('/v1/me/wallet', needAuth, needMember, wrap(async (_req, res) => { res.json(await social.wallet(me(res).id)); }));
  app.get('/v1/me/quests', needAuth, needMember, wrap(async (_req, res) => { res.json(await social.quests(me(res).id)); }));
  app.post('/v1/quests/:id/claim', needAuth, needMember, wrap(async (req, res) => {
    try { res.json(await social.claim(me(res).id, String(req.params.id))); } catch (e) { socialErr(e); }
  }));

  const searchLimit = new RateLimiter(20, 1);
  app.get('/v1/users/search', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    if (!searchLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'Slow down');
    const q = String(req.query.q ?? '').trim().toLowerCase().replace(/^@/, '');
    if (q.length < 2 || !/^[a-z0-9_]{2,20}$/.test(q)) { res.json({ users: [] }); return; }
    const blocked = await d.repo.blockedIds(p.id);
    const hits = await d.repo.searchHandles(q, 40, [p.id, ...blocked]);
    const out = [];
    for (const h of hits) {
      if (out.length >= 12) break;
      if (!sameBand(p, await d.repo.getProfile(h.id))) continue;        // teens and adults do not find each other
      if (!(await d.repo.blockedEitherWay(p.id, h.id))) out.push(h);
    }
    res.json({ users: out });
  }));

  app.get('/v1/duels', needAuth, needMember, wrap(async (_req, res) => {
    const list = await social.list(me(res).id);
    res.json({ duels: list.map((x) => duelView(x, me(res).id)) });
  }));

  app.get('/v1/duels/ideas', needAuth, needMember, wrap(async (req, res) => {
    try { res.json({ ideas: await social.ideas(String(req.query.target ?? '').slice(0, 64), 6, me(res)) }); } catch (e) { socialErr(e); }
  }));

  const duelLimit = new RateLimiter(10, 10 / 3600);
  app.post('/v1/duels', needAuth, needMember, wrap(async (req, res) => {
    if (!duelLimit.take(me(res).id)) throw new HttpError(429, 'rate_limited', 'You are sending duels too quickly');
    try {
      const b = req.body ?? {};
      const duel = await social.create(me(res), {
        targetId: typeof b.targetId === 'string' ? b.targetId : undefined, targetHandle: typeof b.targetHandle === 'string' ? b.targetHandle : undefined,
        libraryIndex: typeof b.libraryIndex === 'number' ? b.libraryIndex : undefined, custom: b.custom && typeof b.custom === 'object' ? b.custom : undefined,
      });
      res.status(201).json({ duel: duelView(duel, me(res).id) });
    } catch (e) { socialErr(e); }
  }));

  for (const action of ['accept', 'decline', 'cancel'] as const) {
    app.post(`/v1/duels/:id/${action}`, needAuth, needMember, wrap(async (req, res) => {
      try { res.json({ duel: duelView(await social.respond(me(res).id, String(req.params.id), action), me(res).id) }); } catch (e) { socialErr(e); }
    }));
  }
  app.post('/v1/duels/:id/submit', needAuth, needMember, wrap(async (req, res) => {
    try { res.json({ duel: duelView(await social.submit(me(res).id, String(req.params.id), { note: req.body?.note, clipId: req.body?.clipId }), me(res).id) }); } catch (e) { socialErr(e); }
  }));
  app.post('/v1/duels/:id/judge', needAuth, needMember, wrap(async (req, res) => {
    try {
      const r = await social.judge(me(res).id, String(req.params.id), req.body?.approve === true);
      res.json({ duel: duelView(r.duel, me(res).id), paid: r.paid, capped: r.capped });
    } catch (e) { socialErr(e); }
  }));

  // Self-declared age screening. This is a screen, not identity verification (docs/threat-model.md).
  const ageLimit = new RateLimiter(5, 5 / 3600);
  app.post('/v1/me/age', needAuth, wrap(async (req, res) => {
    const p = me(res);
    if (!ageLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'Too many attempts');
    // The first answer is final. Without this a 16-year-old could simply enter an adult birthday and switch age band.
    // An answer that was too young is stored (unverified) so it cannot be retried; it becomes valid by itself on the 16th birthday.
    if (p.birthDate) {
      if (!bandForAge(ageFrom(p.birthDate))) throw new HttpError(403, 'underage', `DAREWIRE is for people aged ${MIN_AGE} and over`);
      const done = p.ageVerifiedAt ? p : await d.repo.setAge(p.id, p.birthDate, true);
      res.json({ profile: selfView(done) });
      return;
    }
    const birthDate = String(req.body?.birthDate ?? '');
    const age = ageFrom(birthDate);
    if (age === null) throw bad('bad_date', 'Enter your date of birth as YYYY-MM-DD');
    if (!bandForAge(age)) {
      await d.repo.setAge(p.id, birthDate, false);
      throw new HttpError(403, 'underage', `DAREWIRE is for people aged ${MIN_AGE} and over`);
    }
    res.json({ profile: selfView(await d.repo.setAge(p.id, birthDate, true)) });
  }));

  app.delete('/v1/me', needAuth, wrap(async (_req, res) => {
    const p = me(res);
    d.manager.dropUser(p.id);
    await d.repo.deleteUser(p.id);
    if (d.cfg.supabaseUrl && d.cfg.supabaseServiceKey) {
      const r = await fetch(`${d.cfg.supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(p.id)}`, { method: 'DELETE', headers: { apikey: d.cfg.supabaseServiceKey, authorization: `Bearer ${d.cfg.supabaseServiceKey}` } });
      if (!r.ok) log('warn', 'supabase user delete failed', { status: r.status });
    }
    res.status(204).end();
  }));

  app.get('/v1/me/history', needAuth, needMember, wrap(async (_req, res) => { res.json({ history: await d.repo.history(me(res).id, 50) }); }));
  // ---- following, chat, activity ----
  const followLimit = new RateLimiter(20, 0.3), chatLimit = new RateLimiter(12, 0.5);
  const graphRoute = (fn: (p: Profile, req: Request) => Promise<unknown>): RequestHandler => wrap(async (req, res) => { try { res.json(await fn(me(res), req)); } catch (e) { socialErr(e); } });
  const idParam = (req: Request, name = 'id') => String(req.params[name]).slice(0, 64);

  app.post('/v1/users/:id/follow', needAuth, needMember, graphRoute(async (p, req) => { if (!followLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'Slow down'); return graph.follow(p, idParam(req)); }));
  app.delete('/v1/users/:id/follow', needAuth, needMember, graphRoute((p, req) => graph.unfollow(p, idParam(req))));
  app.get('/v1/users/:id/followers', needAuth, needMember, graphRoute(async (p, req) => ({ people: await graph.followers(p, idParam(req)) })));
  app.get('/v1/users/:id/following', needAuth, needMember, graphRoute(async (p, req) => ({ people: await graph.following(p, idParam(req)) })));
  app.get('/v1/people/suggested', needAuth, needMember, graphRoute(async (p) => ({ people: await graph.suggested(p) })));

  app.get('/v1/chats', needAuth, needMember, graphRoute(async (p) => ({ chats: await graph.chats(p) })));
  app.post('/v1/chats', needAuth, needMember, graphRoute((p, req) => graph.openChat(p, String(req.body?.userId ?? '').slice(0, 64))));
  app.get('/v1/chats/:id', needAuth, needMember, graphRoute((p, req) => graph.thread(p, idParam(req))));
  app.post('/v1/chats/:id/messages', needAuth, needMember, graphRoute(async (p, req) => { if (!chatLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'You are sending messages very fast. Take a breath.'); return graph.send(p, idParam(req), req.body?.text); }));
  app.post('/v1/chats/:id/accept', needAuth, needMember, graphRoute((p, req) => graph.respond(p, idParam(req), true)));
  app.post('/v1/chats/:id/decline', needAuth, needMember, graphRoute((p, req) => graph.respond(p, idParam(req), false)));

  app.get('/v1/activity', needAuth, needMember, graphRoute((p) => graph.activity(p)));
  app.post('/v1/activity/read', needAuth, needMember, wrap(async (_req, res) => { await graph.markActivityRead(me(res)); res.status(204).end(); }));
  app.get('/v1/badges', needAuth, needMember, graphRoute((p) => graph.badges(p)));

  app.get('/v1/leaderboard', needAuth, needMember, wrap(async (_req, res) => {
    const viewer = me(res);
    const rows = await d.repo.leaderboard(viewer.role === 'user' ? 100 : 25);
    const out = [];
    for (const r of rows) {
      if (out.length >= 25) break;
      if (sameBand(viewer, await d.repo.getProfile(r.userId))) out.push(r);
    }
    res.json({ leaderboard: out });
  }));

  // ---- sessions -----------------------------------------------------------------------------------------------

  app.get('/v1/sessions', needAuth, needMember, wrap(async (_req, res) => { res.json({ sessions: d.manager.listPublic(me(res)) }); }));

  const createLimit = new RateLimiter(5, 5 / 3600);
  app.post('/v1/sessions', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    const existing = d.manager.hostedBy(p.id);
    if (existing) { res.status(409).json({ error: { code: 'already_hosting', message: 'You are already hosting a session' }, sessionId: existing }); return; }
    if (!createLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'You are creating sessions too quickly');
    const title = cleanText(String(req.body?.title ?? ''));
    if (title.length < 3 || title.length > 40 || /https?:|www\.|@/i.test(title)) throw bad('bad_title', 'Titles are 3-40 characters with no links');
    const fast = d.cfg.devAuth && req.body?.fast === true;   // short timers for demos; never available in production
    const out = await d.manager.create(p, {
      title, twist: req.body?.twist !== false, visibility: req.body?.visibility === 'private' ? 'private' : 'public', hostPlays: req.body?.hostPlays !== false,
      timings: fast ? { voteMs: 8000, reviewMs: 10000, submissionMs: 8000, verdictMs: 8000, resultMs: 20000, twistVoteMs: 5000 } : undefined,
    });
    res.status(201).json(out);
  }));

  app.post('/v1/sessions/join', needAuth, needMember, wrap(async (req, res) => {
    const rt = d.manager.byCode(String(req.body?.code ?? ''), me(res));   // a session of the other age band answers like a wrong code
    if (!rt) throw new HttpError(404, 'not_found', 'No live session has that code');
    res.json({ sessionId: rt.game.s.id });
  }));

  app.post('/v1/sessions/:id/media-token', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    const r = await d.manager.mediaToken(p.id, p.handle ?? 'player', String(req.params.id), p.role);
    if (!r.ok) throw new HttpError(r.code === 'media_unavailable' ? 503 : r.code === 'not_found' ? 404 : 403, r.code, r.message);
    res.json(r.data);
  }));

  // ---- other people's profiles ---------------------------------------------------------------------------------

  app.get('/v1/users/:id', needAuth, needMember, wrap(async (req, res) => {
    const viewer = me(res);
    const id = String(req.params.id).slice(0, 64);
    const target = await d.repo.getProfile(id);
    if (!target || !target.handle) throw new HttpError(404, 'not_found', 'Profile not found');
    if (!sameBand(viewer, target)) throw new HttpError(404, 'not_found', 'Profile not found');   // teens and adults cannot see each other's accounts
    if (id !== viewer.id && (await d.repo.blockedIds(id)).includes(viewer.id)) throw new HttpError(404, 'not_found', 'Profile not found');
    const iBlocked = id !== viewer.id && (await d.repo.blockedIds(viewer.id)).includes(id);
    const stats = await d.repo.userStats(id);
    const clips = iBlocked ? [] : await d.repo.clipsByAuthor(id, 30);
    const urls = await signed(clips);
    const recent = iBlocked ? [] : (await d.repo.history(id, 12)).map((r) => ({ round: r.round, title: r.challengeTitle, outcome: r.outcome, points: r.playerPoints, at: r.at }));
    const relation = await graph.relation(viewer, target);
    res.json({
      profile: { id: target.id, handle: target.handle, avatar: target.avatar, bio: target.bio, accent: target.accent, joinedAt: target.createdAt, staff: target.role !== 'user' },
      relation, isMe: id === viewer.id, iBlocked, stats, badges: badgesFor(stats, target), recent,
      clips: clips.filter((c) => urls[c.storagePath]).map((c) => feedItem(c, urls, viewer.id, req)),
    });
  }));

  // ---- Cipher (AI companion) -----------------------------------------------------------------------------------

  const cipherLimit = new RateLimiter(6, 0.25);   // a burst of 6, then one message every 4 s per user
  app.post('/v1/cipher/chat', needAuth, needMember, wrap(async (req, res) => {
    if (!cipherLimit.take(me(res).id)) throw new HttpError(429, 'rate_limited', 'Cipher needs a second. Try again in a moment.');
    try {
      const r = await d.cipher.reply({ messages: req.body?.messages, loyalty: req.body?.loyalty, tone: req.body?.tone, name: me(res).handle, hour: req.body?.hour, ctx: req.body?.ctx, band: bandOf(me(res)) ?? 'adult' });
      res.json(r);
    } catch (e) {
      if (e instanceof CipherError) throw bad('bad_chat', e.message);
      throw e;
    }
  }));

  // ---- feed and clips ------------------------------------------------------------------------------------------

  /** Demo clips are served from this server, so their URL is made absolute from the host the app used to reach us. */
  const absolute = (req: Request, u: string | undefined): string | null => (!u ? null : u.startsWith('/') ? `${req.protocol}://${req.get('host')}${u}` : u);
  const feedItem = (c: Clip & { liked?: boolean }, urls: Record<string, string>, viewer: string, req: Request) => ({
    id: c.id, videoUrl: absolute(req, urls[c.storagePath]),
    poster: c.storagePath.startsWith('url:') ? absolute(req, urls[c.storagePath]?.replace(/\.mp4$/, '.jpg')) : null, title: c.title, caption: c.caption, category: c.category, difficulty: c.difficulty,
    twist: c.twist, durationMs: c.durationMs, likes: c.likes, views: c.views, liked: !!c.liked, mine: c.authorId === viewer,
    demo: c.storagePath.startsWith('url:'), publishedAt: c.publishedAt,
    author: { id: c.authorId, handle: c.authorHandle, avatar: c.authorAvatar },
  });
  const signed = async (clips: Clip[]) => (d.storage ? d.storage.sign(clips.map((c) => c.storagePath)) : Object.fromEntries(clips.filter((c) => c.storagePath.startsWith('url:')).map((c) => [c.storagePath, c.storagePath.slice(4)])));

  app.get('/v1/feed', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    const following = req.query.sort === 'following';
    const sort: 'hot' | 'new' = req.query.sort === 'hot' ? 'hot' : 'new';
    const page = Math.max(0, Math.min(200, Number(req.query.page) || 0));
    const blocked = await d.repo.blockedIds(p.id);
    const q = { viewerId: p.id, sort: (following ? 'new' : sort) as 'hot' | 'new', limit: 8, blocked: blocked.filter((x) => /^[0-9a-f-]{36}$/i.test(x) || !d.cfg.databaseUrl), onlyAuthors: following ? await d.repo.followingIds(p.id, 500) : undefined };
    if (following && q.onlyAuthors!.length === 0) { res.json({ items: [], nextPage: null }); return; }
    // Teens and adults see each other's clips on neither feed. The band is checked on the author's account, a few pages at a time,
    // until there is something to show. (If feed volume grows, store the band on the clip row instead.)
    const rows: FeedRow[] = [];
    const bandOk = new Map<string, boolean>();
    const isUser = p.role === 'user';
    let next: number | null = page;
    for (let i = 0; i < (isUser ? 5 : 1) && next !== null && rows.length < 4; i++) {
      const batch = await d.repo.listFeed({ ...q, page: next });
      for (const c of batch) {
        if (isUser && !bandOk.has(c.authorId)) bandOk.set(c.authorId, sameBand(p, await d.repo.getProfile(c.authorId)));
        if (!isUser || bandOk.get(c.authorId)) rows.push(c);
      }
      next = batch.length === 8 ? next + 1 : null;
    }
    const urls = await signed(rows);
    res.json({ items: rows.filter((c) => urls[c.storagePath]).map((c) => feedItem(c, urls, p.id, req)), nextPage: next });
  }));

  const likeLimit = new RateLimiter(30, 1);
  const viewLimit = new RateLimiter(60, 2);
  for (const [method, on] of [['post', true], ['delete', false]] as const) {
    app[method]('/v1/clips/:id/like', needAuth, needMember, wrap(async (req, res) => {
      if (!likeLimit.take(me(res).id)) throw new HttpError(429, 'rate_limited', 'Slow down');
      const r = await d.repo.setLike(String(req.params.id), me(res).id, on);
      if (!r) throw new HttpError(404, 'not_found', 'Clip not found');
      if (on) {   // tell the author (once per person per clip). Demo clips have no account to tell.
        const clip = await d.repo.getClip(String(req.params.id));
        if (clip && clip.authorId !== me(res).id && (await d.repo.getProfile(clip.authorId))) await graph.notify(clip.authorId, 'like', me(res).id, clip.id);
      }
      res.json(r);
    }));
  }

  app.post('/v1/clips/:id/view', needAuth, needMember, wrap(async (req, res) => {
    if (viewLimit.take(me(res).id)) await d.repo.recordView(String(req.params.id), me(res).id);
    res.status(204).end();
  }));

  // The Player's decision. Nothing is public until this is called.
  app.post('/v1/clips/:id/publish', needAuth, needMember, wrap(async (req, res) => {
    const caption = cleanText(String(req.body?.caption ?? '')).slice(0, 140);
    if (/https?:|www\.|@/i.test(caption)) throw bad('bad_caption', 'Captions cannot contain links or handles');
    const clip = await d.repo.publishClip(String(req.params.id), me(res).id, caption);
    if (!clip) throw new HttpError(404, 'not_found', 'Nothing to publish');
    d.manager.clearOffer(me(res).id, clip.id);
    res.json({ id: clip.id });
  }));

  app.delete('/v1/clips/:id', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    const clip = await d.repo.getClip(String(req.params.id));
    if (!clip || (clip.authorId !== p.id && p.role === 'user')) throw new HttpError(404, 'not_found', 'Clip not found');
    await d.repo.deleteClip(clip.id);
    await d.storage?.remove(clip.storagePath);
    d.manager.clearOffer(clip.authorId, clip.id);
    if (clip.authorId !== p.id) await d.repo.logModeration({ moderatorId: p.id, action: 'remove_clip', targetUserId: clip.authorId, note: clip.id });
    res.status(204).end();
  }));

  app.get('/v1/me/clips', needAuth, needMember, wrap(async (_req, res) => {
    const rows = await d.repo.myClips(me(res).id);
    const urls = await signed(rows);
    res.json({ items: rows.map((c) => ({ ...feedItem(c, urls, me(res).id, _req), status: c.status })) });
  }));

  // ---- safety: reports and blocks -----------------------------------------------------------------------------

  const reportLimit = new RateLimiter(10, 10 / 3600);
  app.post('/v1/reports', needAuth, needMember, wrap(async (req, res) => {
    const p = me(res);
    if (!reportLimit.take(p.id)) throw new HttpError(429, 'rate_limited', 'Too many reports');
    const kind = String(req.body?.kind ?? '');
    if (!REPORT_KINDS.includes(kind)) throw bad('bad_kind', 'Unknown report type');
    // Reporting from a chat attaches the last few messages so a moderator can see what was said (the reporter is a member of that chat).
    const transcript = typeof req.body?.conversationId === 'string' ? await graph.transcript(p, req.body.conversationId.slice(0, 64)) : null;
    const note = (cleanText(String(req.body?.note ?? '')).slice(0, 160) + (transcript ? ` [chat] ${transcript}` : '')).slice(0, 500);
    const rep = await d.repo.createReport({
      reporterId: p.id, kind, note,
      targetUserId: typeof req.body?.targetUserId === 'string' ? req.body.targetUserId : undefined,
      sessionId: typeof req.body?.sessionId === 'string' ? req.body.sessionId : undefined,
      clipId: typeof req.body?.clipId === 'string' ? req.body.clipId : undefined,
    });
    // Three different people reporting a clip hides it at once, pending human review.
    if (typeof req.body?.clipId === 'string' && (await d.repo.clipReporterCount(req.body.clipId)) >= 3) await d.repo.setClipStatus(req.body.clipId, 'hidden');
    res.status(201).json({ id: rep.id });
  }));

  app.get('/v1/blocks', needAuth, needMember, wrap(async (_req, res) => {
    const ids = await d.repo.blockedIds(me(res).id);
    const people = [];
    for (const id of ids.slice(0, 100)) { const q = await d.repo.getProfile(id); if (q?.handle) people.push({ id, handle: q.handle, avatar: q.avatar }); }
    res.json({ blocked: ids, people });
  }));
  app.post('/v1/blocks', needAuth, needMember, wrap(async (req, res) => {
    const target = String(req.body?.userId ?? '');
    if (!target || target === me(res).id) throw bad('bad_target', 'Invalid user');
    await d.repo.addBlock(me(res).id, target);
    await d.repo.removeFollow(me(res).id, target); await d.repo.removeFollow(target, me(res).id);   // blocking ends any following, both ways
    res.status(204).end();
  }));
  app.delete('/v1/blocks/:userId', needAuth, needMember, wrap(async (req, res) => { await d.repo.removeBlock(me(res).id, String(req.params.userId)); res.status(204).end(); }));

  // ---- moderation (role-gated; every action is written to moderation_actions) ----------------------------------

  app.get('/v1/mod/reports', needAuth, needMod, wrap(async (req, res) => { res.json({ reports: await d.repo.listReports(req.query.status === 'resolved' ? 'resolved' : 'open') }); }));
  app.get('/v1/mod/clips', needAuth, needMod, wrap(async (_req, res) => {
    const rows = await d.repo.clipsByStatus('hidden');
    res.json({ items: rows.map((c) => ({ id: c.id, title: c.title, caption: c.caption, author: c.authorHandle, authorId: c.authorId })) });
  }));
  app.post('/v1/mod/clips/:id/:action', needAuth, needMod, wrap(async (req, res) => {
    const clip = await d.repo.getClip(String(req.params.id));
    if (!clip) throw new HttpError(404, 'not_found', 'Clip not found');
    if (req.params.action === 'restore') await d.repo.setClipStatus(clip.id, 'published');
    else if (req.params.action === 'remove') { await d.repo.deleteClip(clip.id); await d.storage?.remove(clip.storagePath); }
    else throw bad('bad_action', 'restore or remove');
    await d.repo.logModeration({ moderatorId: me(res).id, action: `clip_${req.params.action}`, targetUserId: clip.authorId, note: clip.id });
    res.status(204).end();
  }));
  app.get('/v1/mod/sessions', needAuth, needMod, wrap(async (_req, res) => { res.json({ sessions: d.manager.listAll() }); }));

  app.post('/v1/mod/reports/:id/resolve', needAuth, needMod, wrap(async (req, res) => {
    const action = String(req.body?.action ?? '');
    if (!['dismiss', 'warn', 'kick', 'suspend_24h', 'suspend_7d'].includes(action)) throw bad('bad_action', 'Unknown action');
    const rep = await d.repo.resolveReport(String(req.params.id), me(res).id, action, cleanText(String(req.body?.note ?? '')));
    if (!rep) throw new HttpError(404, 'not_found', 'Report not found or already resolved');
    if (rep.targetUserId && action.startsWith('suspend')) {
      await d.repo.suspend(rep.targetUserId, new Date(Date.now() + (action === 'suspend_7d' ? 7 : 1) * 86_400_000).toISOString());
      d.manager.dropUser(rep.targetUserId);
    }
    if (rep.targetUserId && action === 'kick' && rep.sessionId) await d.manager.moderate(rep.sessionId, me(res), 'kick', rep.targetUserId);
    await d.repo.logModeration({ moderatorId: me(res).id, action: `report_${action}`, targetUserId: rep.targetUserId ?? undefined, sessionId: rep.sessionId ?? undefined, reportId: rep.id, note: cleanText(String(req.body?.note ?? '')) });
    res.json({ report: rep });
  }));

  for (const [path, action] of [['end', 'end'], ['cut', 'cut']] as const) {
    app.post(`/v1/mod/sessions/:id/${path}`, needAuth, needMod, wrap(async (req, res) => {
      const r = await d.manager.moderate(String(req.params.id), me(res), action);
      if (!r.ok) throw new HttpError(r.code === 'not_found' ? 404 : 409, r.code, r.message);
      res.status(204).end();
    }));
  }

  // ---- development helpers (never mounted in production) -------------------------------------------------------

  if (d.cfg.devAuth) {
    app.post('/v1/dev/sessions/:id/bots', needAuth, wrap(async (req, res) => {
      const rt = d.manager.get(String(req.params.id));
      if (!rt || rt.game.s.config.hostId !== me(res).id) throw new HttpError(403, 'forbidden', 'Only the host can add simulated viewers');
      const n = Math.max(1, Math.min(40, Number(req.body?.count) || 6));
      res.json({ added: d.manager.addBots(String(req.params.id), n), note: 'Simulated viewers: ids start with sim:' });
    }));
  }

  app.use((_req, _res, next) => next(new HttpError(404, 'not_found', 'Not found')));
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) { res.status(err.status).json({ error: { code: err.code, message: err.message } }); return; }
    if ((err as { type?: string })?.type === 'entity.too.large') { res.status(413).json({ error: { code: 'too_large', message: 'Request too large' } }); return; }
    if (err instanceof SyntaxError) { res.status(400).json({ error: { code: 'bad_json', message: 'Invalid JSON' } }); return; }
    log('error', 'unhandled', { err: err instanceof Error ? err.message : 'unknown' });
    res.status(500).json({ error: { code: 'internal', message: 'Something went wrong' } });
  });

  return app;
}
