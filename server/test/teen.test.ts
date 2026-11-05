// Teen (16-17) protections. Every rule here is enforced by the server; the app only mirrors it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { MemoryRepo } from '../src/store/memory.ts';
import { createApp } from '../src/http/app.ts';
import { SessionManager } from '../src/realtime/manager.ts';
import { Director } from '../src/director/director.ts';
import { Cipher } from '../src/cipher/service.ts';
import { loadConfig } from '../src/util/config.ts';
import { seedDemoClips } from '../src/seed.ts';
import { bandForAge, bandOf, sameBand, MIN_AGE } from '../src/profile/age.ts';
import { FALLBACK_DRAFTS, checkPolicy, withAudience, sanitizeBoundaries, DEFAULT_BOUNDARIES, TEEN_FLOOR, type ChallengeDraft } from '../src/policy/index.ts';
import { GameSession, viewFor } from '../src/engine/index.ts';
import { approveChallenge } from '../src/director/approve.ts';
import type { LlmClient, LlmRequest } from '../src/director/llm.ts';
import { seeded, user } from './helpers.ts';

// Dates of birth relative to today, so the tests never go stale.
const yearsAgo = (years: number, extraDays = 0) => {
  const d = new Date(); d.setUTCFullYear(d.getUTCFullYear() - years); d.setUTCDate(d.getUTCDate() - extraDays);
  return d.toISOString().slice(0, 10);
};
const DOB = { child: yearsAgo(15, 30), teen: yearsAgo(16, 2), teen17: yearsAgo(17, 100), adult: yearsAgo(18, 2), grown: '1990-01-01' };

async function world(llm: LlmClient | null = null) {
  const cfg = loadConfig({ NODE_ENV: 'test', DEV_AUTH: 'true' });
  const repo = new MemoryRepo();
  const director = new Director({ llm: null, review: false, rng: seeded(2), uid: () => Math.random().toString(36).slice(2) });
  const manager = new SessionManager({ repo, director, media: null, storage: null });
  const app = createApp({ cfg, repo, manager, verify: async (t) => { const [, id, handle] = t.split(':'); return { id: id!, handleHint: handle }; }, storage: null, cipher: new Cipher(llm) });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (who: string, method: string, path: string, body?: unknown) => {
    const r = await fetch(base + path, { method, headers: { authorization: `Bearer dev:${who}`, 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    return { status: r.status, json: text && r.headers.get('content-type')?.includes('json') ? JSON.parse(text) : null, headers: r.headers, raw: text };
  };
  /** Creates an account that has passed the age gate with this birth date. */
  const member = async (id: string, handle: string, dob: string) => { const who = `${id}:${handle}`; await call(who, 'POST', '/v1/me/age', { birthDate: dob }); return who; };
  return { server, call, member, repo, manager, base, close: () => server.close() };
}

// ---- the age gate ----------------------------------------------------------------------------------------------

test('age bands: under 16 is refused, 16-17 are teens, 18 and over are adults', () => {
  assert.equal(MIN_AGE, 16);
  assert.equal(bandForAge(null), null); assert.equal(bandForAge(15), null);
  assert.equal(bandForAge(16), 'teen'); assert.equal(bandForAge(17), 'teen');
  assert.equal(bandForAge(18), 'adult'); assert.equal(bandForAge(40), 'adult');
});

test('age gate: under 16 is refused, and the first answer is final (no retrying with a different birthday)', async () => {
  const w = await world();
  try {
    const who = 'kid001:kid';
    let r = await w.call(who, 'POST', '/v1/me/age', { birthDate: DOB.child });
    assert.equal(r.status, 403); assert.equal(r.json.error.code, 'underage');
    r = await w.call(who, 'POST', '/v1/me/age', { birthDate: DOB.grown });              // lying the second time does not work
    assert.equal(r.status, 403); assert.equal(r.json.error.code, 'underage');
    r = await w.call(who, 'GET', '/v1/me'); assert.equal(r.json.needs.age, true);
    r = await w.call(who, 'GET', '/v1/feed'); assert.equal(r.status, 403);               // nothing in the app is open to them
    assert.equal((await w.call(who, 'GET', '/v1/sessions')).status, 403);
  } finally { w.close(); }
});

test('age gate: a teen cannot become an adult by answering again', async () => {
  const w = await world();
  try {
    const who = await w.member('teen01', 'tessa', DOB.teen);
    let r = await w.call(who, 'GET', '/v1/me');
    assert.equal(r.json.profile.band, 'teen'); assert.deepEqual(r.json.profile.teenFloor.excludedThemes, ['romance', 'dark_humor']);
    r = await w.call(who, 'POST', '/v1/me/age', { birthDate: DOB.grown });
    assert.equal(r.status, 200); assert.equal(r.json.profile.band, 'teen');
    assert.equal((await w.call(who, 'GET', '/v1/me')).json.profile.band, 'teen');
    const adult = await w.member('adult1', 'arlo', DOB.adult);
    const a = (await w.call(adult, 'GET', '/v1/me')).json.profile; assert.equal(a.band, 'adult'); assert.equal(a.teenFloor, null);
  } finally { w.close(); }
});

// ---- the content floor -----------------------------------------------------------------------------------------

test('teen floor: adds exclusions and a difficulty cap on top of the player\'s own boundaries, and never mutates its input', () => {
  const own = sanitizeBoundaries({ excludedThemes: ['singing'], maxDifficulty: 5 });
  const t = withAudience(own, 'teen');
  assert.equal(t.audience, 'teen'); assert.equal(t.maxDifficulty, 3);
  assert.ok(t.excludedCategories.includes('social_courage'));
  for (const th of ['singing', 'romance', 'dark_humor']) assert.ok(t.excludedThemes.includes(th as never), th);
  assert.deepEqual(own.excludedThemes, ['singing']);                                      // input untouched
  assert.equal(withAudience(sanitizeBoundaries({ maxDifficulty: 2 }), 'teen').maxDifficulty, 2);   // a lower cap of their own is kept
  assert.equal(withAudience(own, 'adult').audience, undefined); assert.equal(withAudience(own, 'adult').maxDifficulty, 5);
  assert.equal(sanitizeBoundaries({ audience: 'adult', maxDifficulty: 5 }).audience, undefined);    // a client can never set the audience
});

test('teen floor: the dare library still has plenty to offer, across several categories', () => {
  const teen = withAudience(DEFAULT_BOUNDARIES, 'teen');
  const ok = FALLBACK_DRAFTS.filter((d) => checkPolicy(d, teen).ok);
  assert.ok(ok.length >= 20, `only ${ok.length} dares pass`);
  assert.ok(new Set(ok.map((d) => d.category)).size >= 4);
  assert.ok(ok.every((d) => d.difficulty <= TEEN_FLOOR.maxDifficulty && d.category !== 'social_courage'));
});

test('teen word rules: pressure, going public, money, meeting people and body image are rejected for teens only', () => {
  const draft = (title: string, objective: string): ChallengeDraft => ({ category: 'perform', title, objective, durationSeconds: 40, difficulty: 2, completionCriteria: ['It is done'], allowedModifiers: [], scoringType: 'audience_judgment', tags: [] });
  const teen = withAudience(DEFAULT_BOUNDARIES, 'teen'), adult = withAudience(DEFAULT_BOUNDARIES, 'adult');
  const bad: [string, string, string][] = [
    ['Prove It', 'Do it to prove yourself to everyone watching.', 'teen_humiliation'],
    ['Go Viral', 'Perform a dance and plan to go viral with it.', 'teen_going_public'],
    ['Quiet Meetup', 'Describe how you would meet up in person with a new friend.', 'teen_meeting_people'],
    ['Cash Talk', 'Explain how you would spend your money on a surprise.', 'teen_money'],
    ['Looks Check', 'Describe your diet and weight as a narrator would.', 'teen_body_image'],
  ];
  for (const [title, objective, reason] of bad) {
    const t = checkPolicy(draft(title, objective), teen);
    assert.ok(t.reasons.includes(reason), `${title}: ${t.reasons.join(',')}`);
    assert.ok(!checkPolicy(draft(title, objective), adult).reasons.includes(reason), `${title} should not be a teen reason for adults`);
  }
  assert.equal(checkPolicy(draft('No Pressure Poem', 'Recite a short poem with no embarrassing voices, in a calm tone.'), teen).ok, true);   // negation is understood
});

test('engine: a teen session applies the floor even when the client sends no boundaries at all, and the view says so', () => {
  let n = 0;
  const deps = { now: () => 1_000_000, rng: seeded(), uid: () => `id${++n}`, approve: approveChallenge };
  const g = GameSession.create({ id: 's1', code: 'TEEN22', title: 'Teens', hostId: 'host', band: 'teen' }, deps);
  g.join(user('host'), { handle: 'host', avatar: 'a01' }, 'player');
  assert.equal(viewFor(g.s, 'host', 1_000_000).boundaries.teen, true);                   // already true in the lobby
  g.startRun(user('host'));
  const r = g.playerReady(user('host'), { excludedCategories: [], excludedThemes: [], maxDifficulty: 5, audience: 'adult' });   // a hostile client
  assert.equal(r.ok, true);
  const v = viewFor(g.s, 'host', 1_000_000);
  assert.equal(v.band, 'teen'); assert.equal(v.boundaries.teen, true); assert.equal(v.boundaries.maxDifficulty, 3);
  assert.ok(v.boundaries.excludedCategories.includes('social_courage')); assert.ok(v.boundaries.excludedThemes.includes('romance'));
  // an adult session is untouched
  const a = GameSession.create({ id: 's2', code: 'ADULT2', title: 'Adults', hostId: 'h2' }, deps);
  assert.equal(viewFor(a.s, null, 0).band, 'adult'); assert.equal(viewFor(a.s, null, 0).boundaries.teen, false); assert.equal(a.s.boundaries.maxDifficulty, 5);
});

// ---- separation: live sessions, search, duels, profiles, leaderboard, feed ---------------------------------------

test('sessions: teens and adults never see, find or join each other\'s sessions (staff can)', async () => {
  const w = await world();
  try {
    const teen = await w.member('teen01', 'tessa', DOB.teen), teen2 = await w.member('teen02', 'theo', DOB.teen17), adult = await w.member('adult1', 'arlo', DOB.grown);
    const mod = await w.member('mod001', 'mody', DOB.grown); await w.repo.setRole('mod001', 'moderator');
    const t = await w.call(teen, 'POST', '/v1/sessions', { title: 'Teen night', visibility: 'public' }); assert.equal(t.status, 201);
    const a = await w.call(adult, 'POST', '/v1/sessions', { title: 'Grown night', visibility: 'public' }); assert.equal(a.status, 201);
    const titles = async (who: string) => (await w.call(who, 'GET', '/v1/sessions')).json.sessions.map((s: { title: string }) => s.title);
    assert.deepEqual(await titles(teen2), ['Teen night']); assert.deepEqual(await titles(adult), ['Grown night']);
    assert.deepEqual((await titles(mod)).sort(), ['Grown night', 'Teen night']);
    // joining by code: the other band gets exactly the answer a wrong code gets
    let r = await w.call(adult, 'POST', '/v1/sessions/join', { code: t.json.code }); assert.equal(r.status, 404);
    const wrong = await w.call(adult, 'POST', '/v1/sessions/join', { code: 'ZZZZZZ' }); assert.equal(r.json.error.message, wrong.json.error.message);
    r = await w.call(teen2, 'POST', '/v1/sessions/join', { code: t.json.code }); assert.equal(r.status, 200);
    r = await w.call(teen, 'POST', '/v1/sessions/join', { code: a.json.code }); assert.equal(r.status, 404);
    assert.equal((await w.call(mod, 'POST', '/v1/sessions/join', { code: t.json.code })).status, 200);
    // and the realtime door is shut too
    const rt = w.manager.get(t.json.id)!;
    const sent: unknown[] = [];
    const client = (userId: string) => ({ id: userId, userId, role: 'user' as const, observer: false, blocked: new Set<string>(), send: (m: unknown) => { sent.push(m); }, close: () => undefined });
    const prof = (await w.repo.getProfile('adult1'))!;
    const res = await w.manager.connect(client('adult1'), rt.game.s.id, prof, 'watcher');
    assert.equal(res.ok, false); assert.equal(res.ok === false && res.code, 'not_found');
    assert.equal(sent.length, 0); assert.equal(rt.game.s.participants['adult1'], undefined);
    assert.equal((await w.manager.connect(client('teen02'), rt.game.s.id, (await w.repo.getProfile('teen02'))!, 'watcher')).ok, true);
    // the session itself is a teen session, so its dares carry the floor
    assert.equal(rt.game.s.config.band, 'teen'); assert.equal(rt.game.s.boundaries.audience, 'teen');
  } finally { w.close(); }
});

test('search, profiles and the leaderboard stay inside the age band', async () => {
  const w = await world();
  try {
    const teen = await w.member('teen01', 'sam_teen', DOB.teen), teen2 = await w.member('teen02', 'sam_teen2', DOB.teen17), adult = await w.member('adult1', 'sam_adult', DOB.grown);
    assert.deepEqual((await w.call(adult, 'GET', '/v1/users/search?q=sam')).json.users.map((u: { handle: string }) => u.handle), []);
    assert.deepEqual((await w.call(teen, 'GET', '/v1/users/search?q=sam')).json.users.map((u: { handle: string }) => u.handle), ['sam_teen2']);
    assert.equal((await w.call(adult, 'GET', '/v1/users/teen01')).status, 404);
    assert.equal((await w.call(teen, 'GET', '/v1/users/adult1')).status, 404);
    assert.equal((await w.call(teen, 'GET', '/v1/users/teen02')).status, 200);
    // give everyone points so they would all be on the board
    for (const id of ['teen01', 'teen02', 'adult1']) await w.repo.addPoints({ userId: id, amount: 50, kind: 'quest', ref: 'test', key: `t:${id}`, note: 'test' });
    const board = async (who: string) => (await w.call(who, 'GET', '/v1/leaderboard')).json.leaderboard.map((r: { handle: string }) => r.handle);
    assert.deepEqual((await board(adult)), ['sam_adult']);                                   // an adult sees only adults
    assert.deepEqual((await board(teen2)).sort(), ['sam_teen', 'sam_teen2']);               // a teen sees only teens
  } finally { w.close(); }
});

test('duels: never across bands, and teens pick from the dare ideas instead of writing their own', async () => {
  const w = await world();
  try {
    const teen = await w.member('teen01', 'tessa', DOB.teen), teen2 = await w.member('teen02', 'theo', DOB.teen17), adult = await w.member('adult1', 'arlo', DOB.grown);
    await w.member('teen03', 'tina', DOB.teen);
    // cross-band: indistinguishable from "no such player", in both directions
    for (const [from, to] of [[adult, 'teen01'], [teen, 'adult1']] as const) {
      assert.equal((await w.call(from, 'GET', `/v1/duels/ideas?target=${to}`)).status, 404);
      const r = await w.call(from, 'POST', '/v1/duels', { targetId: to, libraryIndex: 0 });
      assert.equal(r.status, 404); assert.equal(r.json.error.code, 'not_found');
      assert.equal((await w.call(from, 'POST', '/v1/duels', { targetHandle: to === 'teen01' ? 'tessa' : 'arlo', libraryIndex: 0 })).status, 404);
    }
    // teen to teen: ideas all respect the floor; a custom dare is refused; a curated one goes through
    const ideas = (await w.call(teen, 'GET', '/v1/duels/ideas?target=teen02')).json.ideas as { index: number; difficulty: number; category: string }[];
    assert.ok(ideas.length >= 5); assert.ok(ideas.every((i) => i.difficulty <= 3 && i.category !== 'social_courage'));
    let r = await w.call(teen, 'POST', '/v1/duels', { targetId: 'teen02', custom: { title: 'My own dare', objective: 'Say something about your day out loud.' } });
    assert.equal(r.status, 400); assert.match(r.json.error.message, /pick from the dare ideas/);
    r = await w.call(teen, 'POST', '/v1/duels', { targetId: 'teen02', libraryIndex: ideas[0]!.index }); assert.equal(r.status, 201);
    // a library dare that breaks the floor (level 5, social courage) is refused even if the client names its index directly
    const hard = FALLBACK_DRAFTS.findIndex((d) => d.difficulty === 5 || d.category === 'social_courage');
    r = await w.call(teen2, 'POST', '/v1/duels', { targetId: 'teen03', libraryIndex: hard }); assert.equal(r.status, 400); assert.equal(r.json.error.code, 'unsafe_dare');
    // adults keep custom dares
    const adult2 = await w.member('adult2', 'ada', DOB.grown);
    r = await w.call(adult, 'POST', '/v1/duels', { targetId: 'adult2', custom: { title: 'Poem time', objective: 'Recite a short poem in a calm voice.' } }); assert.equal(r.status, 201);
    void adult2;
  } finally { w.close(); }
});

test('feed: teen clips are not shown to adults and the other way round; demo clips are shown to everyone', async () => {
  const w = await world();
  try {
    await seedDemoClips(w.repo);
    const teen = await w.member('teen01', 'tessa', DOB.teen), adult = await w.member('adult1', 'arlo', DOB.grown), mod = await w.member('mod001', 'mody', DOB.grown);
    await w.repo.setRole('mod001', 'moderator');
    const mk = async (id: string, handle: string, title: string) => w.repo.createClip({ authorId: id, authorHandle: handle, authorAvatar: 'a01', title, category: 'perform', difficulty: 2, durationMs: 4000, storagePath: 'url:/demo/dare-dino.mp4', status: 'published' });
    await mk('teen01', 'tessa', 'Teen clip'); await mk('adult1', 'arlo', 'Adult clip');
    const titles = async (who: string) => (await w.call(who, 'GET', '/v1/feed?sort=new')).json.items.map((i: { title: string }) => i.title);
    const t = await titles(teen), a = await titles(adult), m = await titles(mod);
    assert.ok(t.includes('Teen clip') && !t.includes('Adult clip'));
    assert.ok(a.includes('Adult clip') && !a.includes('Teen clip'));
    assert.ok(m.includes('Teen clip') && m.includes('Adult clip'));
    for (const list of [t, a, m]) assert.ok(list.includes('Dino Shopping Run') && list.includes('Karaoke Solo'));
  } finally { w.close(); }
});

// ---- Cipher ------------------------------------------------------------------------------------------------------

test('Cipher gets the teen rules from the server\'s age record, and a client cannot ask for them or switch them off', async () => {
  const seen: LlmRequest[] = [];
  const w = await world({ json: async (r) => { seen.push(r); return { messages: ['ok'], mood: 'idle', loyaltyDelta: 0 }; } });
  try {
    const teen = await w.member('teen01', 'tessa', DOB.teen), adult = await w.member('adult1', 'arlo', DOB.grown);
    const msgs = [{ role: 'user', text: 'hey' }];
    await w.call(teen, 'POST', '/v1/cipher/chat', { messages: msgs, band: 'adult', ctx: { band: 'adult' } });
    await w.call(adult, 'POST', '/v1/cipher/chat', { messages: msgs, band: 'teen' });
    assert.equal(seen.length, 2);
    assert.match(seen[0]!.system, /TEEN ACCOUNT/); assert.match(seen[0]!.system, /pressuring them/);
    assert.doesNotMatch(seen[1]!.system, /TEEN ACCOUNT/);
    for (const s of seen) assert.doesNotMatch(s.system, /adult player|adults-only|18\+/);
  } finally { w.close(); }
});

// ---- demo videos -------------------------------------------------------------------------------------------------

test('demo clips: the five videos are served with posters, and the feed hands out absolute URLs', async () => {
  const w = await world();
  try {
    await seedDemoClips(w.repo);
    const who = await w.member('adult1', 'arlo', DOB.grown);
    const items = (await w.call(who, 'GET', '/v1/feed')).json.items as { videoUrl: string; poster: string; demo: boolean; title: string }[];
    assert.equal(items.length, 5); assert.ok(items.every((i) => i.demo));
    for (const i of items) {
      assert.match(i.videoUrl, /^http:\/\/127\.0\.0\.1:\d+\/demo\/dare-[a-z]+\.mp4$/); assert.match(i.poster, /\/demo\/dare-[a-z]+\.jpg$/);
      const v = await fetch(i.videoUrl); assert.equal(v.status, 200); assert.equal(v.headers.get('content-type'), 'video/mp4');
      const p = await fetch(i.poster); assert.equal(p.status, 200); assert.equal(p.headers.get('content-type'), 'image/jpeg');
    }
    assert.equal((await fetch(w.base + '/demo/../package.json')).status, 404);          // static serving cannot escape its folder
  } finally { w.close(); }
});

test('sameBand / bandOf: staff see both bands; demo authors (no account) are open to all', () => {
  const t = { birthDate: DOB.teen, role: 'user' as const }, a = { birthDate: DOB.grown, role: 'user' as const }, m = { birthDate: null, role: 'moderator' as const };
  assert.equal(bandOf(t), 'teen'); assert.equal(bandOf(a), 'adult'); assert.equal(bandOf(m), 'adult');
  assert.equal(sameBand(t, a), false); assert.equal(sameBand(a, t), false); assert.equal(sameBand(t, t), true);
  assert.equal(sameBand(m, t), true); assert.equal(sameBand(t, m), true); assert.equal(sameBand(t, null), true);
  assert.equal(bandOf({ birthDate: null, role: 'user' }), null);
});
