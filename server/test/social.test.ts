import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { MemoryRepo } from '../src/store/memory.ts';
import { SocialService, SocialError, RULES, computeStreak, weekStrip, utcDay, duelReward, QUESTS } from '../src/social/service.ts';
import { createApp } from '../src/http/app.ts';
import { SessionManager } from '../src/realtime/manager.ts';
import { Director } from '../src/director/director.ts';
import { Cipher } from '../src/cipher/service.ts';
import { loadConfig } from '../src/util/config.ts';
import { DEFAULT_AVATAR, isCustomAvatar } from '../src/util/ids.ts';
import type { Profile } from '../src/store/types.ts';
import { seeded } from './helpers.ts';

const T0 = Date.parse('2026-10-28T12:00:00.000Z');

async function world() {
  const repo = new MemoryRepo();
  const clock = { t: T0 };
  repo.clock = () => clock.t;
  let n = 0;
  const svc = new SocialService({ repo, now: () => clock.t, rng: seeded(5), uid: () => `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}` });
  const mk = async (id: string, handle: string): Promise<Profile> => {
    await repo.ensureProfile(id); await repo.updateProfile(id, { handle }); return repo.setAge(id, '1990-01-01');
  };
  const a = await mk('user-a', 'alice'); const b = await mk('user-b', 'bob'); const c = await mk('user-c', 'cara');
  return { repo, svc, clock, a, b, c, mk };
}

const rejects = async (p: Promise<unknown>, code: string) => {
  await assert.rejects(p, (e: unknown) => e instanceof SocialError && e.code === code, `expected ${code}`);
};

test('a duel runs challenge -> accept -> submit -> approve, and pays the target and the challenger', async () => {
  const w = await world();
  const d = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 });
  assert.equal(d.status, 'pending'); assert.equal(d.origin, 'library');
  await w.svc.respond('user-b', d.id, 'accept');
  await w.svc.submit('user-b', d.id, { note: 'done it' });
  const r = await w.svc.judge('user-a', d.id, true);
  assert.equal(r.duel.status, 'completed');
  assert.equal(r.paid, duelReward(d.difficulty));
  assert.equal((await w.repo.userStats('user-b')).points, r.paid);
  assert.equal((await w.repo.userStats('user-a')).points, RULES.challengerBonus);
  assert.equal((await w.repo.userStats('user-b')).duels, 1);
});

test('only the right person can take each step, and steps cannot be skipped', async () => {
  const w = await world();
  const d = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 1 });
  await rejects(w.svc.respond('user-a', d.id, 'accept'), 'forbidden');          // the challenger cannot accept for them
  await rejects(w.svc.submit('user-b', d.id, {}), 'bad_state');                 // not accepted yet
  await rejects(w.svc.judge('user-a', d.id, true), 'bad_state');                // nothing to judge
  await rejects(w.svc.respond('user-c', d.id, 'accept'), 'not_found');          // outsiders cannot even see it
  await w.svc.respond('user-b', d.id, 'accept');
  await rejects(w.svc.respond('user-b', d.id, 'accept'), 'bad_state');
  await w.svc.submit('user-b', d.id, {});
  await rejects(w.svc.judge('user-b', d.id, true), 'forbidden');                // you cannot approve your own work
  const r = await w.svc.judge('user-a', d.id, false);
  assert.equal(r.duel.status, 'rejected'); assert.equal(r.paid, 0);
  assert.equal((await w.repo.userStats('user-b')).points, 0);
});

test('guards: no self duels, no blocked players, one open duel per pair, and a limit on open duels', async () => {
  const w = await world();
  await rejects(w.svc.create(w.a, { targetId: 'user-a', libraryIndex: 0 }), 'bad_target');
  await w.repo.addBlock('user-b', 'user-a');
  await rejects(w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 }), 'blocked');
  await w.repo.removeBlock('user-b', 'user-a');
  await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 });
  await rejects(w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 2 }), 'already_open');
  await rejects(w.svc.create(w.b, { targetId: 'user-a', libraryIndex: 2 }), 'already_open');   // either direction
  for (let i = 0; i < RULES.maxOpenOutgoing - 1; i++) { const p = await w.mk(`extra-${i}`, `extra${i}`); await w.svc.create(w.a, { targetId: p.id, libraryIndex: 3 }); }
  const last = await w.mk('extra-last', 'extralast');
  await rejects(w.svc.create(w.a, { targetId: last.id, libraryIndex: 3 }), 'too_many');
});

test('custom dares go through the safety policy and the target\'s boundaries', async () => {
  const w = await world();
  await rejects(w.svc.create(w.a, { targetId: 'user-b', custom: { title: 'ok', objective: 'too short' } }), 'bad_dare');
  await rejects(w.svc.create(w.a, { targetId: 'user-b', custom: { title: 'Visit my page', objective: 'Go to https://example.com and sign up' } }), 'bad_dare');
  const good = await w.svc.create(w.a, { targetId: 'user-b', custom: { title: 'Weather report', objective: 'Give a serious weather forecast for your living room.', difficulty: 2, category: 'perform' } });
  assert.equal(good.origin, 'custom');
  await w.svc.respond('user-b', good.id, 'decline');
  // a target who ruled out the 'perform' category cannot be sent one
  await w.repo.updateProfile('user-c', { boundaries: { excludedCategories: ['perform'], excludedThemes: [], maxDifficulty: 5 } });
  await rejects(w.svc.create(w.a, { targetId: 'user-c', custom: { title: 'Weather report', objective: 'Give a serious weather forecast for your living room.', category: 'perform' } }), 'unsafe_dare');
});

test('ideas respect the target\'s boundaries', async () => {
  const w = await world();
  await w.repo.updateProfile('user-b', { boundaries: { excludedCategories: ['perform', 'create'], excludedThemes: [], maxDifficulty: 2 } });
  const ideas = await w.svc.ideas('user-b', 20);
  assert.ok(ideas.length > 0);
  for (const i of ideas) { assert.ok(!['perform', 'create'].includes(i.category)); assert.ok(i.difficulty <= 2); }
});

test('duels expire if nobody answers, and expired duels pay nothing', async () => {
  const w = await world();
  const d = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 });
  w.clock.t += RULES.ttlMs.pending + 1000;
  await rejects(w.svc.respond('user-b', d.id, 'accept'), 'expired');
  assert.equal((await w.svc.list('user-a'))[0]!.status, 'expired');
  // the pair is free to duel again
  await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 1 });
});

test('anti-farming: only the first approved duel between the same two people each day pays', async () => {
  const w = await world();
  const d1 = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 });
  await w.svc.respond('user-b', d1.id, 'accept'); await w.svc.submit('user-b', d1.id, {});
  assert.ok((await w.svc.judge('user-a', d1.id, true)).paid > 0);
  const d2 = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 1 });
  await w.svc.respond('user-b', d2.id, 'accept'); await w.svc.submit('user-b', d2.id, {});
  const r2 = await w.svc.judge('user-a', d2.id, true);
  assert.equal(r2.paid, 0); assert.equal(r2.capped, true); assert.equal(r2.duel.status, 'completed');
  // the next day it pays again
  w.clock.t += 86_400_000;
  const d3 = await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 2 });
  await w.svc.respond('user-b', d3.id, 'accept'); await w.svc.submit('user-b', d3.id, {});
  assert.ok((await w.svc.judge('user-a', d3.id, true)).paid > 0);
});

test('anti-farming: a daily cap applies across different opponents', async () => {
  const w = await world();
  let total = 0;
  for (let i = 0; i < 8; i++) {
    const p = await w.mk(`friend-${i}`, `friend${i}`);
    const d = await w.svc.create(p, { targetId: 'user-b', libraryIndex: 5 });   // a level 4 dare pays 50
    await w.svc.respond('user-b', d.id, 'accept'); await w.svc.submit('user-b', d.id, {});
    total += (await w.svc.judge(p.id, d.id, true)).paid;
  }
  assert.equal(total, RULES.dailyCapTarget);
});

test('quests: progress comes from real activity, can be claimed once a day, and pays the ledger', async () => {
  const w = await world();
  let q = await w.svc.quests('user-a');
  assert.equal(q.quests.find((x) => x.id === 'send_duel')!.progress, 0);
  await rejects(w.svc.claim('user-a', 'send_duel'), 'not_done');
  await w.svc.create(w.a, { targetId: 'user-b', libraryIndex: 0 });
  q = await w.svc.quests('user-a');
  assert.equal(q.quests.find((x) => x.id === 'send_duel')!.progress, 1);
  const paid = await w.svc.claim('user-a', 'send_duel');
  assert.equal(paid.amount, QUESTS.find((x) => x.id === 'send_duel')!.reward);
  await rejects(w.svc.claim('user-a', 'send_duel'), 'claimed');
  assert.equal((await w.svc.wallet('user-a')).balance, paid.amount);
  await rejects(w.svc.claim('user-a', 'nope'), 'not_found');
  w.clock.t += 86_400_000;                     // next day: the quest resets (and needs new activity)
  q = await w.svc.quests('user-a');
  assert.equal(q.quests.find((x) => x.id === 'send_duel')!.claimed, false);
  assert.equal(q.quests.find((x) => x.id === 'send_duel')!.progress, 0);
});

test('streak maths and the week strip', () => {
  const days = (...d: string[]) => new Set(d);
  const now = Date.parse('2026-10-29T10:00:00Z');   // a Thursday
  assert.equal(computeStreak(days(), now), 0);
  assert.equal(computeStreak(days('2026-10-29', '2026-10-28', '2026-10-27'), now), 3);
  assert.equal(computeStreak(days('2026-10-28', '2026-10-27'), now), 2);          // today not played yet: streak is kept
  assert.equal(computeStreak(days('2026-10-27'), now), 0);                         // missed yesterday: streak is gone
  const w = weekStrip(days('2026-10-26', '2026-10-29'), now);
  assert.equal(w.length, 7); assert.equal(w[0]!.day, '2026-10-26'); assert.equal(w[0]!.active, true);
  assert.equal(w[3]!.today, true); assert.equal(w[6]!.future, true);
  assert.equal(utcDay(now), '2026-10-29');
});

test('wallet never promises cash-out', async () => {
  const w = await world();
  const wallet = await w.svc.wallet('user-a');
  assert.equal(wallet.cashOut.available, false);
});

// ---- HTTP: avatar upload ------------------------------------------------------------------------------------------

async function httpWorld() {
  const cfg = loadConfig({ NODE_ENV: 'test', DEV_AUTH: 'true' });
  const repo = new MemoryRepo();
  const director = new Director({ llm: null, review: false, rng: seeded(2), uid: () => Math.random().toString(36).slice(2) });
  const manager = new SessionManager({ repo, director, media: null, storage: null });
  const app = createApp({ cfg, repo, manager, verify: async (t) => { const [, id, handle] = t.split(':'); return { id: id!, handleHint: handle }; }, storage: null, cipher: new Cipher(null) });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (token: string, method: string, path: string, body?: unknown) => {
    const r = await fetch(base + path, { method, headers: { authorization: `Bearer dev:${token}`, 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    return { status: r.status, json: text && r.headers.get('content-type')?.includes('json') ? JSON.parse(text) : null, headers: r.headers, raw: text };
  };
  const adult = async (id: string, handle: string) => { await call(`${id}:${handle}`, 'POST', '/v1/me/age', { birthDate: '1990-01-01' }); };
  return { server, call, adult, repo, base };
}

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(64, 1)]);

test('HTTP: custom avatar upload validates the real file type and serves it back', async () => {
  const h = await httpWorld();
  try {
    const t = 'abc123:zed'; await h.adult('abc123', 'zed');
    // not an image, even though the client says so
    let r = await h.call(t, 'PUT', '/v1/me/avatar', { data: Buffer.from('<html>hi</html> not an image at all').toString('base64') });
    assert.equal(r.status, 400);
    // too big
    r = await h.call(t, 'PUT', '/v1/me/avatar', { data: Buffer.concat([PNG, Buffer.alloc(520 * 1024)]).toString('base64') });
    assert.equal(r.status, 400);
    // a valid image
    r = await h.call(t, 'PUT', '/v1/me/avatar', { data: PNG.toString('base64') });
    assert.equal(r.status, 200);
    const avatar = r.json.profile.avatar as string;
    assert.ok(isCustomAvatar(avatar), avatar);
    const img = await fetch(h.base + avatar);                         // public: no token needed
    assert.equal(img.status, 200); assert.equal(img.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await img.arrayBuffer()), PNG);
    // a client cannot set the custom path directly, nor an unknown key
    r = await h.call(t, 'PUT', '/v1/me', { avatar: '/v1/avatars/someone-else?v=1' }); assert.equal(r.status, 400);
    r = await h.call(t, 'PUT', '/v1/me', { avatar: 'ghost' }); assert.equal(r.status, 400);
    r = await h.call(t, 'PUT', '/v1/me', { avatar: 'a07' }); assert.equal(r.status, 200);
    r = await h.call(t, 'PUT', '/v1/me', { avatar: 'a15' }); assert.equal(r.status, 400);   // removed avatars are no longer valid
    // removing the photo resets to the default
    r = await h.call(t, 'DELETE', '/v1/me/avatar'); assert.equal(r.json.profile.avatar, DEFAULT_AVATAR);
    assert.equal((await fetch(h.base + avatar)).status, 404);
  } finally { h.server.close(); }
});

test('HTTP: duel flow end to end with user search and wallet', async () => {
  const h = await httpWorld();
  try {
    const ta = 'aaaa11:alice', tb = 'bbbb22:bobby';
    await h.adult('aaaa11', 'alice'); await h.adult('bbbb22', 'bobby');
    let r = await h.call(ta, 'GET', '/v1/users/search?q=bob');
    assert.equal(r.status, 200); assert.equal(r.json.users[0].handle, 'bobby');
    r = await h.call(ta, 'GET', `/v1/duels/ideas?target=bbbb22`); assert.ok(r.json.ideas.length > 0);
    r = await h.call(ta, 'POST', '/v1/duels', { targetId: 'bbbb22', libraryIndex: r.json.ideas[0].index });
    assert.equal(r.status, 201); const id = r.json.duel.id as string;
    assert.equal((await h.call(tb, 'GET', '/v1/duels')).json.duels[0].role, 'target');
    assert.equal((await h.call(tb, 'POST', `/v1/duels/${id}/accept`)).status, 200);
    assert.equal((await h.call(tb, 'POST', `/v1/duels/${id}/submit`, { note: 'easy' })).status, 200);
    assert.equal((await h.call(tb, 'POST', `/v1/duels/${id}/judge`, { approve: true })).status, 403);   // not the challenger
    r = await h.call(ta, 'POST', `/v1/duels/${id}/judge`, { approve: true });
    assert.equal(r.status, 200); assert.ok(r.json.paid > 0);
    const w = await h.call(tb, 'GET', '/v1/me/wallet');
    assert.equal(w.json.balance, r.json.paid); assert.equal(w.json.cashOut.available, false);
    const q = await h.call(tb, 'POST', '/v1/quests/finish_duel/claim'); assert.equal(q.status, 200);
  } finally { h.server.close(); }
});
