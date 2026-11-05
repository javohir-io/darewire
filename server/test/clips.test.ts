import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Recorder, type RecCtx } from '../src/realtime/recorder.ts';
import { MemoryRepo } from '../src/store/memory.ts';
import type { Egress } from '../src/media/egress.ts';
import type { Clip } from '../src/store/types.ts';

const tick = (ms = 15) => new Promise((r) => setTimeout(r, ms));
const ev = (type: string, data: Record<string, unknown> = {}) => ({ rev: 1, type, data });
const ctx = (over: Partial<RecCtx> = {}): RecCtx => ({
  sessionId: 's1', phase: 'LIVE_ROUND', allowClips: true, player: { id: 'p1', handle: 'player', avatar: 'fox' },
  round: { n: 1, title: 'Sock Court', category: 'perform', difficulty: 3, twist: null }, ...over,
});

function harness() {
  const log: string[] = [];
  const egress: Egress = { start: async (_s, f) => { log.push('start:' + f); return 'eg1'; }, stop: async () => { log.push('stop'); }, status: async () => 'complete' };
  const removed: string[] = [];
  const offered: Clip[] = [];
  const repo = new MemoryRepo();
  const rec = new Recorder({ repo, egress, storage: { sign: async () => ({}), remove: async (p) => { removed.push(p); } }, onReady: (_s, _u, c) => offered.push(c), sleep: async () => undefined, pollMs: 1 });
  return { rec, log, removed, offered, repo };
}

test('consent: nothing is recorded unless the Player allowed clips for this run', async () => {
  const h = harness();
  h.rec.handle(ctx({ allowClips: false }), [ev('accepted')]);
  await tick();
  assert.deepEqual(h.log, []);
  assert.equal(h.rec.active(), 0);
});

test('a completed round is recorded, stopped at the end of the attempt, and offered to the Player (not published)', async () => {
  const h = harness();
  h.rec.handle(ctx(), [ev('accepted')]);
  h.rec.handle(ctx({ phase: 'SUBMISSION' }), [ev('phase', { phase: 'SUBMISSION' })]);
  await tick();
  assert.ok(h.log[0]!.startsWith('start:clips/s1/1-')); assert.ok(h.log.includes('stop'));
  h.rec.handle(ctx({ phase: 'ROUND_RESULT' }), [ev('round:result', { round: 1, outcome: 'completed' })]);
  await tick();
  assert.equal(h.offered.length, 1);
  assert.equal(h.offered[0]!.status, 'awaiting');
  assert.equal(h.offered[0]!.title, 'Sock Court');
  assert.equal((await h.repo.listFeed({ viewerId: 'x', sort: 'new', page: 0, limit: 10, blocked: [] })).length, 0);   // not public yet
  assert.equal(h.rec.active(), 0);
});

test('Safety Stop, moderator cut and abandoned rounds delete the recording and never offer it', async () => {
  for (const [kind, ev1] of [['safety', ev('safety:stop')], ['cut', ev('stream:cut')], ['end', ev('session:ended')]] as const) {
    const h = harness();
    h.rec.handle(ctx(), [ev('accepted')]);
    h.rec.handle(ctx({ phase: 'ROUND_RESULT' }), [ev1, ev('round:result', { round: 1, outcome: 'safety_stop' })]);
    await tick();
    assert.equal(h.offered.length, 0, kind);
    assert.equal(h.removed.length, 1, kind);
    assert.equal((await h.repo.clipsByStatus('awaiting')).length, 0, kind);
  }
  const h = harness();
  h.rec.handle(ctx(), [ev('accepted')]);
  h.rec.handle(ctx({ phase: 'ROUND_RESULT' }), [ev('round:result', { round: 1, outcome: 'abandoned' })]);
  await tick();
  assert.equal(h.offered.length, 0); assert.equal(h.removed.length, 1);
});

test('egress failures never break the game and never create a clip', async () => {
  const h = harness();
  const bad: Egress = { start: async () => { throw new Error('no egress'); }, stop: async () => undefined, status: async () => 'failed' };
  const rec = new Recorder({ repo: h.repo, egress: bad, storage: null, onReady: () => assert.fail('must not offer'), sleep: async () => undefined });
  rec.handle(ctx(), [ev('accepted')]);
  rec.handle(ctx({ phase: 'ROUND_RESULT' }), [ev('round:result', { round: 1, outcome: 'completed' })]);
  await tick();
  assert.equal((await h.repo.clipsByStatus('awaiting')).length, 0);
});

test('feed: only published clips, hot ranking favours engagement and unseen clips, new sorts by time, blocked authors hidden', async () => {
  const repo = new MemoryRepo();
  let t = Date.parse('2026-10-28T12:00:00Z'); repo.clock = () => t;
  const mk = async (id: string, author: string) => repo.createClip({ authorId: author, authorHandle: author, authorAvatar: 'cat', title: id, category: 'create', difficulty: 2, durationMs: 1000, storagePath: `url:${id}`, status: 'published' });
  const a = await mk('old-but-loved', 'ann'); t += 3_600_000; const b = await mk('fresh', 'bob'); t += 3_600_000; const c = await mk('newest', 'cy');
  const draft = await repo.createClip({ authorId: 'dee', authorHandle: 'dee', authorAvatar: 'cat', title: 'draft', category: 'create', difficulty: 1, durationMs: 1, storagePath: 'x' });
  for (const u of ['u1', 'u2', 'u3', 'u4', 'u5', 'u6']) { await repo.setLike(a.id, u, true); await repo.recordView(a.id, u); }
  const q = { viewerId: 'viewer', page: 0, limit: 10, blocked: [] as string[] };
  assert.deepEqual((await repo.listFeed({ ...q, sort: 'new' })).map((x) => x.title), ['newest', 'fresh', 'old-but-loved']);
  assert.equal((await repo.listFeed({ ...q, sort: 'hot' }))[0]!.title, 'old-but-loved');
  assert.ok(!(await repo.listFeed({ ...q, sort: 'new' })).some((x) => x.id === draft.id));
  await repo.recordView(a.id, 'viewer');                                           // seen clips sink for that viewer
  assert.notEqual((await repo.listFeed({ ...q, sort: 'hot' }))[0]!.title, 'old-but-loved');
  assert.equal((await repo.listFeed({ ...q, sort: 'new', blocked: ['cy'] })).some((x) => x.title === 'newest'), false);
  assert.equal((await repo.setLike(b.id, 'viewer', true))!.likes, 1);
  assert.equal((await repo.setLike(b.id, 'viewer', true))!.likes, 1);              // idempotent
  assert.equal((await repo.setLike(b.id, 'viewer', false))!.likes, 0);
  assert.equal(await repo.setLike(draft.id, 'viewer', true), null);                // cannot like unpublished clips
  void c;
});

test('publishing: only the author can publish, once, and unpublished clips expire', async () => {
  const repo = new MemoryRepo();
  let t = 1_000_000; repo.clock = () => t;
  const clip = await repo.createClip({ authorId: 'p1', authorHandle: 'p', authorAvatar: 'cat', title: 'T', category: 'perform', difficulty: 1, durationMs: 1, storagePath: 'a.mp4' });
  assert.equal(await repo.publishClip(clip.id, 'intruder', 'hi'), null);
  assert.equal((await repo.publishClip(clip.id, 'p1', 'my caption'))!.status, 'published');
  assert.equal(await repo.publishClip(clip.id, 'p1', 'again'), null);
  const old = await repo.createClip({ authorId: 'p1', authorHandle: 'p', authorAvatar: 'cat', title: 'old', category: 'perform', difficulty: 1, durationMs: 1, storagePath: 'b.mp4' });
  t += 25 * 3_600_000;
  const gone = await repo.expireAwaiting(24 * 3_600_000);
  assert.deepEqual(gone.map((c) => c.id), [old.id]);
});
