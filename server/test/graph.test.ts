// Following, direct messages and activity: the rules, especially the ones that protect 16-17 year olds.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { MemoryRepo } from '../src/store/memory.ts';
import { createApp } from '../src/http/app.ts';
import { SessionManager } from '../src/realtime/manager.ts';
import { Director } from '../src/director/director.ts';
import { Cipher } from '../src/cipher/service.ts';
import { loadConfig } from '../src/util/config.ts';
import { moderateMessage } from '../src/social/chat-policy.ts';
import { seeded } from './helpers.ts';

const yearsAgo = (y: number, d = 0) => { const t = new Date(); t.setUTCFullYear(t.getUTCFullYear() - y); t.setUTCDate(t.getUTCDate() - d); return t.toISOString().slice(0, 10); };
const TEEN = yearsAgo(16, 3), ADULT = '1990-01-01';

async function world() {
  const cfg = loadConfig({ NODE_ENV: 'test', DEV_AUTH: 'true' });
  const repo = new MemoryRepo();
  const director = new Director({ llm: null, review: false, rng: seeded(3), uid: () => Math.random().toString(36).slice(2) });
  const manager = new SessionManager({ repo, director, media: null, storage: null });
  const app = createApp({ cfg, repo, manager, verify: async (t) => { const [, id, handle] = t.split(':'); return { id: id!, handleHint: handle }; }, storage: null, cipher: new Cipher(null) });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = async (who: string, method: string, path: string, body?: unknown) => {
    const r = await fetch(base + path, { method, headers: { authorization: `Bearer dev:${who}`, 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    return { status: r.status, json: text && r.headers.get('content-type')?.includes('json') ? JSON.parse(text) : null };
  };
  const member = async (id: string, handle: string, dob: string) => { const who = `${id}:${handle}`; await call(who, 'POST', '/v1/me/age', { birthDate: dob }); return who; };
  return { call, member, repo, close: () => server.close() };
}

// ---- the message filter ------------------------------------------------------------------------------------------

test('message filter: contact details and links are refused for everyone, personal questions and meet-ups for teens', () => {
  const ok = (t: string, teen: boolean) => moderateMessage(t, teen).ok;
  for (const teen of [true, false]) {
    assert.equal(ok('that dare was so good', teen), true);
    for (const bad of ['check https://evil.example/x', 'go to www.foo.bar', 'mail me a@b.com', 'call 555 123 4567', 'add me @cool_kid99', 'visit freeprizes.xyz']) assert.equal(ok(bad, teen), false, bad);
    assert.equal(ok('kys', teen), false);
  }
  for (const bad of ['want to meet up?', 'what school do you go to', 'how old are you', 'add me on snapchat', 'it is our little secret', 'send me a pic', 'are you home alone']) {
    assert.equal(ok(bad, true), false, `teen: ${bad}`);
    assert.equal(ok(bad, false), true, `adult: ${bad}`);
  }
  assert.equal(moderateMessage('   ', true).ok, false);
  assert.equal(moderateMessage('x'.repeat(501), false).ok, false);
  assert.equal((moderateMessage('  hi   there  ', false) as { text: string }).text, 'hi there');   // cleaned
});

// ---- following -------------------------------------------------------------------------------------------------

test('follow: counts, notification, profile relation; not yourself, not across age bands, not when blocked; blocking ends following', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT), b = await w.member('bbb001', 'ben', ADULT), t = await w.member('ttt001', 'tess', TEEN);
    assert.equal((await w.call(a, 'POST', '/v1/users/aaa001/follow')).status, 404);          // yourself
    assert.equal((await w.call(a, 'POST', '/v1/users/ttt001/follow')).status, 404);          // other age band: like a missing person
    assert.equal((await w.call(t, 'POST', '/v1/users/bbb001/follow')).status, 404);
    let r = await w.call(a, 'POST', '/v1/users/bbb001/follow');
    assert.equal(r.status, 200); assert.equal(r.json.isFollowing, true); assert.equal(r.json.followers, 1);
    await w.call(a, 'POST', '/v1/users/bbb001/follow');                                       // twice is fine
    assert.equal((await w.call(b, 'GET', '/v1/users/bbb001')).json.relation.followers, 1);
    const prof = (await w.call(a, 'GET', '/v1/users/bbb001')).json.relation;
    assert.equal(prof.isFollowing, true); assert.equal(prof.followsYou, false); assert.equal(prof.messageMode, 'request');
    const act = (await w.call(b, 'GET', '/v1/activity')).json;                                // ben was told, once
    assert.equal(act.unread, 1); assert.equal(act.items[0].kind, 'follow'); assert.equal(act.items[0].actor.handle, 'ava'); assert.equal(act.items[0].iFollowActor, false);
    assert.equal((await w.call(b, 'GET', '/v1/badges')).json.activity, 1);
    await w.call(b, 'POST', '/v1/activity/read');
    assert.equal((await w.call(b, 'GET', '/v1/badges')).json.activity, 0);
    assert.deepEqual((await w.call(b, 'GET', '/v1/users/bbb001/followers')).json.people.map((p: { handle: string }) => p.handle), ['ava']);
    assert.deepEqual((await w.call(a, 'GET', '/v1/users/aaa001/following')).json.people.map((p: { handle: string }) => p.handle), ['ben']);
    // blocking removes following both ways and stops new follows
    await w.call(b, 'POST', '/v1/blocks', { userId: 'aaa001' });
    assert.equal((await w.call(a, 'GET', '/v1/users/bbb001')).status, 404);
    assert.equal((await w.call(a, 'POST', '/v1/users/bbb001/follow')).status, 404);
    assert.equal(await w.repo.isFollowing('aaa001', 'bbb001'), false);
    assert.equal((await w.call(a, 'DELETE', '/v1/users/bbb001/follow')).json.isFollowing, false);
    void t;
  } finally { w.close(); }
});

test('Following feed: only clips by people you follow', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT); await w.member('bbb001', 'ben', ADULT); await w.member('ccc001', 'cy', ADULT);
    const mk = (id: string, handle: string, title: string) => w.repo.createClip({ authorId: id, authorHandle: handle, authorAvatar: 'a01', title, category: 'perform', difficulty: 2, durationMs: 4000, storagePath: 'url:/demo/dare-dino.mp4', status: 'published' });
    await mk('bbb001', 'ben', 'Ben clip'); await mk('ccc001', 'cy', 'Cy clip');
    assert.deepEqual((await w.call(a, 'GET', '/v1/feed?sort=following')).json.items, []);   // follows nobody yet
    await w.call(a, 'POST', '/v1/users/bbb001/follow');
    const titles = (await w.call(a, 'GET', '/v1/feed?sort=following')).json.items.map((i: { title: string }) => i.title);
    assert.deepEqual(titles, ['Ben clip']);
    assert.equal((await w.call(a, 'GET', '/v1/feed?sort=new')).json.items.length, 2);
  } finally { w.close(); }
});

test('liking a clip tells its author once; liking your own clip tells nobody', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT), b = await w.member('bbb001', 'ben', ADULT);
    const clip = await w.repo.createClip({ authorId: 'bbb001', authorHandle: 'ben', authorAvatar: 'a01', title: 'Ben clip', category: 'perform', difficulty: 2, durationMs: 4000, storagePath: 'url:/demo/dare-dino.mp4', status: 'published' });
    await w.call(a, 'POST', `/v1/clips/${clip.id}/like`); await w.call(a, 'DELETE', `/v1/clips/${clip.id}/like`); await w.call(a, 'POST', `/v1/clips/${clip.id}/like`);
    await w.call(b, 'POST', `/v1/clips/${clip.id}/like`);
    const items = (await w.call(b, 'GET', '/v1/activity')).json.items;
    assert.equal(items.length, 1); assert.equal(items[0].kind, 'like'); assert.equal(items[0].ref, clip.id);
  } finally { w.close(); }
});

// ---- teen chat ------------------------------------------------------------------------------------------------

test('teen chat: only between mutual followers, filtered, and closed again when someone unfollows', async () => {
  const w = await world();
  try {
    const t1 = await w.member('ttt001', 'tess', TEEN), t2 = await w.member('ttt002', 'theo', TEEN);
    // not mutual: no chat at all, and no request path for teens
    let r = await w.call(t1, 'POST', '/v1/chats', { userId: 'ttt002' }); assert.equal(r.status, 403); assert.equal(r.json.error.code, 'chat_not_allowed');
    await w.call(t1, 'POST', '/v1/users/ttt002/follow');
    assert.equal((await w.call(t1, 'POST', '/v1/chats', { userId: 'ttt002' })).status, 403);                // one-way is still not enough
    assert.equal((await w.call(t1, 'GET', '/v1/users/ttt002')).json.relation.messageMode, 'none');
    await w.call(t2, 'POST', '/v1/users/ttt001/follow');
    r = await w.call(t1, 'POST', '/v1/chats', { userId: 'ttt002' }); assert.equal(r.status, 200); assert.equal(r.json.status, 'active');
    const id = r.json.id as string;
    assert.equal((await w.call(t2, 'POST', '/v1/chats', { userId: 'ttt001' })).json.id, id);               // one chat per pair
    // filtered
    for (const bad of ['meet me after school', 'add me on snapchat', 'text me 555 123 4567', 'https://x.example/a']) {
      const m = await w.call(t1, 'POST', `/v1/chats/${id}/messages`, { text: bad }); assert.equal(m.status, 400, bad); assert.equal(m.json.error.code, 'message_blocked');
    }
    assert.equal((await w.call(t1, 'POST', `/v1/chats/${id}/messages`, { text: 'that dare was wild' })).status, 200);
    // unread, read
    assert.equal((await w.call(t2, 'GET', '/v1/badges')).json.chats, 1);
    const th = (await w.call(t2, 'GET', `/v1/chats/${id}`)).json;
    assert.equal(th.teen, true); assert.deepEqual(th.messages.map((m: { text: string; mine: boolean }) => [m.text, m.mine]), [['that dare was wild', false]]); assert.equal(th.canSend, true);
    assert.equal((await w.call(t2, 'GET', '/v1/badges')).json.chats, 0);
    assert.equal((await w.call(t2, 'GET', '/v1/chats')).json.chats[0].lastText, 'that dare was wild');
    // unfollow closes the chat for new messages (the history stays)
    await w.call(t2, 'DELETE', '/v1/users/ttt001/follow');
    const closed = await w.call(t1, 'POST', `/v1/chats/${id}/messages`, { text: 'hello?' });
    assert.equal(closed.status, 403); assert.equal(closed.json.error.code, 'cannot_send');
    assert.equal((await w.call(t1, 'GET', `/v1/chats/${id}`)).json.canSend, false);
  } finally { w.close(); }
});

test('chat is never across age bands, never for outsiders, and blocking hides it', async () => {
  const w = await world();
  try {
    const t = await w.member('ttt001', 'tess', TEEN), t2 = await w.member('ttt002', 'theo', TEEN), a = await w.member('aaa001', 'ava', ADULT), a2 = await w.member('aaa002', 'abe', ADULT);
    assert.equal((await w.call(a, 'POST', '/v1/chats', { userId: 'ttt001' })).status, 404);
    assert.equal((await w.call(t, 'POST', '/v1/chats', { userId: 'aaa001' })).status, 404);
    await w.call(t, 'POST', '/v1/users/ttt002/follow'); await w.call(t2, 'POST', '/v1/users/ttt001/follow');
    const id = (await w.call(t, 'POST', '/v1/chats', { userId: 'ttt002' })).json.id as string;
    for (const outsider of [a, a2]) { assert.equal((await w.call(outsider, 'GET', `/v1/chats/${id}`)).status, 404); assert.equal((await w.call(outsider, 'POST', `/v1/chats/${id}/messages`, { text: 'hi' })).status, 404); }
    await w.call(t2, 'POST', '/v1/blocks', { userId: 'ttt001' });
    assert.equal((await w.call(t, 'GET', `/v1/chats/${id}`)).status, 404);
    assert.deepEqual((await w.call(t, 'GET', '/v1/chats')).json.chats, []);
    assert.equal((await w.call(t2, 'POST', '/v1/chats', { userId: 'ttt001' })).status, 404);
  } finally { w.close(); }
});

// ---- adult message requests ------------------------------------------------------------------------------------

test('adult requests: one message, then the other person decides', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT), b = await w.member('bbb001', 'ben', ADULT);
    const open = await w.call(a, 'POST', '/v1/chats', { userId: 'bbb001' }); assert.equal(open.status, 200); assert.equal(open.json.status, 'request');
    const id = open.json.id as string;
    assert.equal((await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'hey, loved your clip' })).status, 200);
    let r = await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'hello??' }); assert.equal(r.status, 403); assert.match(r.json.error.message, /accept/);
    // ben sees a request, cannot reply before accepting, and was notified
    const row = (await w.call(b, 'GET', '/v1/chats')).json.chats[0]; assert.equal(row.incomingRequest, true); assert.equal(row.status, 'request');
    assert.equal((await w.call(b, 'POST', `/v1/chats/${id}/messages`, { text: 'hi' })).status, 403);
    assert.equal((await w.call(b, 'GET', '/v1/activity')).json.items.some((i: { kind: string }) => i.kind === 'message_request'), true);
    assert.equal((await w.call(a, 'POST', `/v1/chats/${id}/accept`)).status, 400);                         // the sender cannot accept their own request
    assert.equal((await w.call(b, 'POST', `/v1/chats/${id}/accept`)).json.status, 'active');
    assert.equal((await w.call(b, 'POST', `/v1/chats/${id}/messages`, { text: 'thanks!' })).status, 200);
    assert.equal((await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'np' })).status, 200);
    assert.equal((await w.call(a, 'GET', '/v1/activity')).json.items.some((i: { kind: string }) => i.kind === 'request_accepted'), true);
  } finally { w.close(); }
});

test('declined request: closed, hidden, and only a follow-back from the other person reopens it', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT), b = await w.member('bbb001', 'ben', ADULT);
    const id = (await w.call(a, 'POST', '/v1/chats', { userId: 'bbb001' })).json.id as string;
    await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'hey' });
    assert.equal((await w.call(b, 'POST', `/v1/chats/${id}/decline`)).json.status, 'declined');
    assert.deepEqual((await w.call(b, 'GET', '/v1/chats')).json.chats, []);
    assert.equal((await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'please?' })).status, 403);
    assert.equal((await w.call(a, 'POST', '/v1/chats', { userId: 'bbb001' })).status, 403);               // cannot ask again
    await w.call(a, 'POST', '/v1/users/bbb001/follow'); await w.call(b, 'POST', '/v1/users/aaa001/follow');   // now mutual
    const again = await w.call(a, 'POST', '/v1/chats', { userId: 'bbb001' }); assert.equal(again.status, 200); assert.equal(again.json.status, 'active');
  } finally { w.close(); }
});

test('reporting from a chat attaches the last messages for the moderator; blocked list shows who is blocked', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT); await w.member('bbb001', 'ben', ADULT); await w.member('ccc001', 'cy', ADULT);
    await w.call(a, 'POST', '/v1/users/bbb001/follow'); await w.call('bbb001:ben', 'POST', '/v1/users/aaa001/follow');
    const id = (await w.call(a, 'POST', '/v1/chats', { userId: 'bbb001' })).json.id as string;
    await w.call(a, 'POST', `/v1/chats/${id}/messages`, { text: 'first message' });
    const kind = 'harassment';
    const r = await w.call('bbb001:ben', 'POST', '/v1/reports', { kind, targetUserId: 'aaa001', note: 'rude', conversationId: id });
    assert.equal(r.status, 201);
    const rep = w.repo.reports[0]!; assert.match(rep.note, /rude/); assert.match(rep.note, /\[chat\] other: first message/);
    assert.equal((await w.call('ccc001:cy', 'POST', '/v1/reports', { kind, targetUserId: 'aaa001', conversationId: id })).status, 201);   // an outsider's report carries no transcript
    assert.doesNotMatch(w.repo.reports[1]!.note, /first message/);
    await w.call('bbb001:ben', 'POST', '/v1/blocks', { userId: 'aaa001' });
    const blocked = (await w.call('bbb001:ben', 'GET', '/v1/blocks')).json;
    assert.deepEqual(blocked.people.map((p: { handle: string }) => p.handle), ['ava']);
    await w.call('bbb001:ben', 'DELETE', '/v1/blocks/aaa001');
    assert.equal((await w.call('bbb001:ben', 'GET', '/v1/blocks')).json.people.length, 0);
  } finally { w.close(); }
});

test('suggested people: same band only, not yourself, not already followed', async () => {
  const w = await world();
  try {
    const a = await w.member('aaa001', 'ava', ADULT); await w.member('bbb001', 'ben', ADULT); await w.member('ccc001', 'cy', ADULT); await w.member('ttt001', 'tess', TEEN);
    for (const id of ['aaa001', 'bbb001', 'ccc001', 'ttt001']) await w.repo.addPoints({ userId: id, amount: 40, kind: 'quest', ref: 'x', key: `s:${id}`, note: 'x' });
    await w.call(a, 'POST', '/v1/users/bbb001/follow');
    assert.deepEqual((await w.call(a, 'GET', '/v1/people/suggested')).json.people.map((p: { handle: string }) => p.handle), ['cy']);
  } finally { w.close(); }
});
