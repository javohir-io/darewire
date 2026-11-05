// Integration test: the real SessionManager + engine + Director + MemoryRepo, driven by fake socket clients
// over a real (short) clock. No network, no database.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SessionManager, type Client } from '../src/realtime/manager.ts';
import { MemoryRepo } from '../src/store/memory.ts';
import { Director } from '../src/director/director.ts';
import { randomUUID } from 'node:crypto';

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

function fakeClient(userId: string, role: 'user' | 'moderator' = 'user') {
  const inbox: { type: string; data?: any; rev?: number }[] = [];
  const c: Client = { id: randomUUID(), userId, role, observer: false, blocked: new Set(), send: (m) => { inbox.push(m); }, close: () => undefined };
  const last = (type: string) => [...inbox].reverse().find((m) => m.type === type);
  return { c, inbox, last, state: () => last('session:state')!.data };
}

async function profile(repo: MemoryRepo, id: string, handle: string, role: 'user' | 'moderator' = 'user') {
  await repo.ensureProfile(id); await repo.updateProfile(id, { handle }); await repo.setAge(id, '1990-01-01'); if (role !== 'user') await repo.setRole(id, role);
  return (await repo.getProfile(id))!;
}

test('end to end through the manager: create, join, generate, vote, accept, finish, judge, persist', async () => {
  const repo = new MemoryRepo();
  const director = new Director({ llm: null, review: false, rng: Math.random, uid: randomUUID });
  const mgr = new SessionManager({ repo, director, media: null });
  const host = await profile(repo, 'host-1', 'hosty');
  const w1 = await profile(repo, 'watch-1', 'watcher_one');
  const w2 = await profile(repo, 'watch-2', 'watcher_two');

  const { id } = await mgr.create(host, { title: 'Manager test', twist: false, visibility: 'public', hostPlays: true,
    timings: { voteMs: 600, reviewMs: 3000, submissionMs: 3000, verdictMs: 600, resultMs: 5000, readyMs: 5000, generationMs: 5000 } });

  const H = fakeClient('host-1'), A = fakeClient('watch-1'), B = fakeClient('watch-2');
  assert.equal((await mgr.connect(H.c, id, host, 'player')).ok, true);
  assert.equal((await mgr.connect(A.c, id, w1, 'watcher')).ok, true);
  assert.equal((await mgr.connect(B.c, id, w2, 'watcher')).ok, true);
  assert.equal(H.state().you.role, 'player');
  assert.equal(mgr.listPublic().length, 1);

  assert.equal((await mgr.command(A.c, id, 'session:start', {})).ok, false);          // a watcher cannot start the run
  assert.equal((await mgr.command(H.c, id, 'session:start', {})).ok, true);
  assert.equal((await mgr.command(H.c, id, 'player:ready', {})).ok, true);
  await wait(150);                                                                    // the Director (fallback mode) publishes
  assert.equal(H.state().phase, 'CHALLENGE_VOTE');
  assert.equal(H.state().round.options.length, 5);
  assert.equal(A.last('challenge:options') !== undefined, true);

  assert.equal((await mgr.command(A.c, id, 'vote:cast', { option: 2 })).ok, true);
  assert.equal((await mgr.command(B.c, id, 'vote:cast', { option: 2 })).ok, true);
  assert.equal((await mgr.command(B.c, id, 'vote:cast', { option: 4 })).ok, false);   // no changing votes
  await wait(300);                                                                    // vote-only state pushes are coalesced (250 ms)
  assert.equal(A.state().you.vote, 2);
  assert.equal(JSON.stringify(B.state()).includes('watch-1'), true);                  // roster is public, but...
  assert.equal(B.state().you.vote, 2);                                                // ...each user only sees their own ballot

  await wait(400);                                                                    // server timer locks the vote on its own
  assert.equal(H.state().phase, 'PLAYER_REVIEW');
  assert.equal(H.state().round.chosenIdx, 2);
  assert.equal(A.last('vote:locked')!.data.idx, 2);

  assert.equal((await mgr.command(H.c, id, 'challenge:accept', {})).ok, true);
  assert.equal((await mgr.command(H.c, id, 'attempt:finish', {})).ok, true);
  assert.equal((await mgr.command(H.c, id, 'attempt:submit', { note: 'done' })).ok, true);
  await mgr.command(A.c, id, 'verdict:cast', { completed: true });
  await mgr.command(B.c, id, 'verdict:cast', { completed: true });
  await wait(900);
  assert.equal(H.state().phase, 'ROUND_RESULT');
  assert.equal(H.state().round.result.outcome, 'completed');
  assert.ok(H.state().roster.find((p: any) => p.id === 'host-1').score >= 100);

  await wait(50);
  const hist = await repo.history('host-1', 10);                                      // the result was persisted
  assert.equal(hist.length, 1); assert.equal(hist[0]!.outcome, 'completed');
  assert.ok((await repo.loadActiveSessions()).length === 1);                         // and the snapshot is restorable

  // chat: filtered, rate limited, and blocked users are not shown to the blocker
  assert.equal((await mgr.command(A.c, id, 'chat:send', { text: 'nice one' })).ok, true);
  assert.equal((await mgr.command(A.c, id, 'chat:send', { text: 'visit https://x.example now' })).ok, false);
  assert.equal(H.last('chat:message')!.data.text, 'nice one');
  B.c.blocked.add('watch-1');
  await mgr.command(A.c, id, 'chat:send', { text: 'second' });
  assert.notEqual(B.last('chat:message')!.data.text, 'second');

  await mgr.shutdown();
});

test('moderator actions are role-gated and end the session for everyone', async () => {
  const repo = new MemoryRepo();
  const mgr = new SessionManager({ repo, director: new Director({ llm: null, review: false, rng: Math.random, uid: randomUUID }), media: null });
  const host = await profile(repo, 'h', 'hosty'); const mod = await profile(repo, 'm', 'modmod', 'moderator'); const u = await profile(repo, 'u', 'userone');
  const { id } = await mgr.create(host, { title: 'Mod test', twist: false, visibility: 'public', hostPlays: true });
  const H = fakeClient('h'), U = fakeClient('u'), M = fakeClient('m', 'moderator');
  await mgr.connect(H.c, id, host, 'player'); await mgr.connect(U.c, id, u, 'watcher');
  assert.equal((await mgr.connect(fakeClient('u2').c, id, u, 'observer')).ok, false);       // a normal user cannot observe
  assert.equal((await mgr.connect(M.c, id, mod, 'observer')).ok, true);
  assert.equal((await mgr.command(U.c, id, 'mod:end', {})).ok, false);                       // a client cannot use mod commands
  assert.equal((await mgr.command(M.c, id, 'mod:end', {})).ok, true);
  assert.equal(H.state().phase, 'SESSION_END'); assert.equal(U.state().endedReason, 'moderator_ended');
  assert.equal(repo.moderation.length >= 1, true);                                           // audited
  assert.equal((await mgr.connect(fakeClient('late').c, id, u, 'watcher')).ok, false);
  await mgr.shutdown();
});

test('blocked users cannot join a session hosted by the person who blocked them', async () => {
  const repo = new MemoryRepo();
  const mgr = new SessionManager({ repo, director: new Director({ llm: null, review: false, rng: Math.random, uid: randomUUID }), media: null });
  const host = await profile(repo, 'h', 'hosty'); const u = await profile(repo, 'u', 'userone');
  await repo.addBlock('h', 'u');
  const { id } = await mgr.create(host, { title: 'Block test', twist: false, visibility: 'public', hostPlays: true });
  const r = await mgr.connect(fakeClient('u').c, id, u, 'watcher');
  assert.equal(r.ok, false); assert.equal((r as any).code, 'blocked');
  await mgr.shutdown();
});

test('server restart: sessions are restored from the stored snapshot and carry on', async () => {
  const repo = new MemoryRepo();
  const dir = () => new Director({ llm: null, review: false, rng: Math.random, uid: randomUUID });
  const m1 = new SessionManager({ repo, director: dir(), media: null });
  const host = await profile(repo, 'h', 'hosty');
  const { id } = await m1.create(host, { title: 'Restart', twist: false, visibility: 'public', hostPlays: true });
  await wait(20); await m1.shutdown();
  const m2 = new SessionManager({ repo, director: dir(), media: null });
  assert.equal(await m2.restore(), 1);
  const H = fakeClient('h');
  assert.equal((await m2.connect(H.c, id, host, 'player')).ok, true);
  assert.equal(H.state().phase, 'LOBBY'); assert.equal(H.state().you.role, 'player');
  await m2.shutdown();
});
