import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setup, toVote, toLive, user, SYSTEM, MOD, options } from './helpers.ts';
import { GameSession } from '../src/engine/index.ts';
import { pickWinner, playerPoints } from '../src/engine/rules.ts';

// ---------- voting integrity ----------

test('a late vote cannot alter a locked result', async () => {
  const c = setup(); await toVote(c);
  c.g.castVote(user('w0'), 1); c.g.castVote(user('w1'), 1); c.g.castVote(user('w2'), 2);
  c.clock.advance(20_000); c.g.tick();
  assert.equal(c.g.s.phase, 'PLAYER_REVIEW');
  assert.equal(c.g.s.round!.chosenIdx, 1);
  const late = c.g.castVote(user('w2'), 2);
  assert.equal(late.ok, false);
  assert.equal(c.g.s.round!.chosenIdx, 1);
  assert.deepEqual(c.g.s.round!.finalTally, [0, 2, 1, 0, 0]);
});

test('a vote cast after the deadline but before the tick is still refused', async () => {
  const c = setup(); await toVote(c);
  c.clock.advance(20_001);                       // the server timer has not fired yet
  const r = c.g.castVote(user('w0'), 0);
  assert.equal(r.ok, false); assert.equal((r as any).code, 'vote_closed');
});

test('duplicate voting counts once; changing a vote is rejected', async () => {
  const c = setup(); await toVote(c);
  assert.deepEqual(c.g.castVote(user('w0'), 3), { ok: true, duplicate: false });
  assert.deepEqual(c.g.castVote(user('w0'), 3), { ok: true, duplicate: true });
  const change = c.g.castVote(user('w0'), 4);
  assert.equal(change.ok, false); assert.equal((change as any).code, 'already_voted');
  assert.deepEqual(Object.values(c.g.s.round!.votes), [3]);
  assert.equal(c.g.s.participants['w0']!.votesCast, 1);
});

test('only eligible users vote: non-members, the Player and bad indices are refused', async () => {
  const c = setup(); await toVote(c);
  assert.equal((c.g.castVote(user('stranger'), 0) as any).code, 'not_found');
  assert.equal((c.g.castVote(user('host'), 0) as any).code, 'forbidden');
  for (const bad of [-1, 5, 1.5, '2', null, undefined, NaN]) assert.equal(c.g.castVote(user('w0'), bad as any).ok, false);
  assert.equal(Object.keys(c.g.s.round!.votes).length, 0);
});

test('concurrent voting: 200 watchers vote at once and the server produces one correct result', async () => {
  const c = setup({ watchers: 0 }); await toVote(c);
  const counts = [0, 0, 0, 0, 0];
  for (let i = 0; i < 200; i++) {
    c.g.join(user(`v${i}`), { handle: `v${i}`, avatar: 'cat' });
    const idx = i % 7 === 0 ? 4 : i % 3;       // simulated audience, deterministic
    counts[idx]++;
    c.g.castVote(user(`v${i}`), idx);
    c.g.castVote(user(`v${i}`), (idx + 1) % 5); // a second, conflicting vote from the same client must not count
  }
  c.clock.advance(20_000); c.g.tick();
  assert.deepEqual(c.g.s.round!.finalTally, counts);
  assert.equal(c.g.s.round!.finalTally!.reduce((a, b) => a + b, 0), 200);
});

test('tie-break: the option whose final vote arrived first wins; zero votes picks randomly and says so', () => {
  const w = pickWinner({ a: 0, b: 1, c: 0, d: 1 }, { a: 10, b: 20, c: 30, d: 25 }, 5, () => 0);
  assert.equal(w.idx, 1);  // option 1 finished at t=25, option 0 at t=30
  const z = pickWinner({}, {}, 5, () => 0.99);
  assert.equal(z.by, 'no_votes'); assert.equal(z.idx, 4);
});

test('everyone online voting closes the vote early, but never before the minimum window', async () => {
  const c = setup(); await toVote(c);
  for (const w of c.watchers) c.g.castVote(user(w), 2);
  assert.equal(c.g.s.phase, 'CHALLENGE_VOTE');   // too early
  const c2 = setup(); await toVote(c2);
  c2.clock.advance(6_000);
  for (const w of c2.watchers) c2.g.castVote(user(w), 2);
  assert.equal(c2.g.s.phase, 'PLAYER_REVIEW');
});

// ---------- state machine ----------

test('a client cannot advance the game directly or publish options', async () => {
  const c = setup();
  assert.equal((c.g.publishOptions(user('host'), await options(c.director, c.g), 1) as any).code, 'forbidden');
  assert.equal((c.g.startRun(user('w0')) as any).code, 'forbidden');
  assert.equal(c.g.s.phase, 'LOBBY');
  c.g.startRun(user('host'));
  assert.equal((c.g.playerReady(user('w0'), {}) as any).code, 'forbidden');
  assert.equal(c.g.s.phase, 'READY_CHECK');
  // clients have no path to tick/lockVote: the WebSocket layer only exposes the user commands, and users cannot skip phases
  assert.equal((c.g.accept(user('host')) as any).code, 'bad_phase');
  assert.equal((c.g.finish(user('host')) as any).code, 'bad_phase');
  assert.equal((c.g.submit(user('host'), 'x') as any).code, 'bad_phase');
  assert.equal((c.g.next(user('host')) as any).code, 'bad_phase');
});

test('clients cannot change roles or award themselves points', async () => {
  const c = setup(); await toLive(c);
  assert.equal((c.g.handoff(user('w0'), 'w0') as any).code, 'forbidden');
  assert.equal((c.g.finish(user('w0')) as any).code, 'forbidden');
  assert.equal((c.g.safetyStop(user('w0')) as any).code, 'forbidden');
  assert.equal(c.g.s.participants['w0']!.role, 'watcher');
  assert.equal(c.g.s.participants['w0']!.score, 35); // 10 vote + 25 called it, nothing else
});

test('full round: vote, accept, finish, submit, verdict, result; scores are computed by the server', async () => {
  const c = setup(); const { opts } = await toLive(c);
  assert.equal(c.g.s.phase, 'LIVE_ROUND');
  assert.equal(c.g.finish(user('host')).ok, true);
  assert.equal(c.g.submit(user('host'), '  Nailed   it  ').ok, true);
  assert.equal(c.g.s.round!.note, 'Nailed it');
  c.g.castVerdict(user('w0'), true); c.g.castVerdict(user('w1'), true); c.g.castVerdict(user('w2'), false);
  c.clock.advance(15_000); c.g.tick();
  assert.equal(c.g.s.phase, 'ROUND_RESULT');
  const res = c.g.s.round!.result!;
  assert.equal(res.outcome, 'completed'); assert.equal(res.judged, true);
  assert.equal(res.playerPoints, 100 * opts[0]!.difficulty);
  assert.equal(c.g.s.participants['host']!.score, res.playerPoints);
  assert.equal(c.g.s.participants['w0']!.score, 10 + 25 + 10);   // vote + called it + verdict matched majority
  assert.equal(c.g.s.participants['w2']!.score, 10 + 25);        // verdict did not match
  assert.equal(res.streak, 1);
});

test('a failed verdict resets the streak; nobody judging gives half points, never zero', async () => {
  const c = setup(); await toLive(c);
  c.g.finish(user('host')); c.g.submit(user('host'));
  c.g.castVerdict(user('w0'), false); c.g.castVerdict(user('w1'), false); c.g.castVerdict(user('w2'), true);
  c.clock.advance(15_000); c.g.tick();
  assert.equal(c.g.s.round!.result!.outcome, 'failed');
  assert.equal(c.g.s.round!.result!.playerPoints, 0);
  const c2 = setup(); await toLive(c2);
  c2.g.finish(user('host')); c2.g.submit(user('host')); c2.clock.advance(15_000); c2.g.tick();
  const r = c2.g.s.round!.result!;
  assert.equal(r.outcome, 'completed'); assert.equal(r.judged, false);
  assert.equal(r.playerPoints, playerPoints(r.difficulty!, 0, true) / 2);
});

test('expired timers move the state machine on by themselves (server owns the clock)', async () => {
  const c = setup(); await toLive(c);
  c.clock.advance(10 * 60_000); c.g.tick();      // a huge jump: the attempt ends, but later phases still get their own full window
  assert.equal(c.g.s.phase, 'SUBMISSION');
  c.clock.advance(15_000); c.g.tick();
  assert.equal(c.g.s.phase, 'AUDIENCE_VERDICT');
  c.clock.advance(15_000); c.g.tick();
  assert.equal(c.g.s.phase, 'ROUND_RESULT');
  assert.equal(c.g.s.history.length, 1);
  assert.equal(c.g.s.round!.result!.judged, false);
  c.clock.advance(45_000); c.g.tick();
  assert.equal(c.g.s.phase, 'LOBBY');
  assert.equal(c.g.tick(), false);               // idempotent: nothing left to do
});

test('invalid transitions are blocked at every phase', async () => {
  const c = setup(); const { opts } = await toVote(c);
  assert.equal((c.g.accept(user('host')) as any).code, 'bad_phase');                    // still voting
  assert.equal((c.g.castVerdict(user('w0'), true) as any).code, 'bad_phase');
  assert.equal((c.g.publishOptions(SYSTEM, opts, 999) as any).code, 'stale');           // wrong token / wrong phase
  assert.equal((c.g.startRun(user('host')) as any).code, 'bad_phase');
  c.clock.advance(20_000); c.g.tick();
  assert.equal((c.g.castVote(user('w0'), 0) as any).code, 'bad_phase');
});

// ---------- Player autonomy and safety ----------

test('Player can pass: fresh options, same round, no penalty, streak untouched', async () => {
  const c = setup(); await toVote(c);
  c.g.castVote(user('w0'), 0); c.clock.advance(20_000); c.g.tick();
  assert.equal(c.g.s.phase, 'PLAYER_REVIEW');
  assert.equal(c.g.pass(user('host')).ok, true);
  assert.equal(c.g.s.phase, 'CHALLENGE_GENERATION');
  assert.equal(c.g.s.round!.passes, 1);
  assert.equal(c.g.s.participants['host']!.score, 0);
  const fx = c.g.drain().effects.filter((e) => e.type === 'generate') as any[];
  assert.equal(fx.length, 1);
  assert.equal(fx[0].forceFallback, false);
});

test('a watcher cannot farm vote points by forcing passes', async () => {
  const c = setup(); const first = await toVote(c);
  c.g.castVote(user('w0'), 0); c.clock.advance(20_000); c.g.tick();
  const afterFirst = c.g.s.participants['w0']!.score;
  c.g.pass(user('host'));
  const fx = c.g.drain().effects.filter((e) => e.type === 'generate').at(-1) as any;
  c.g.publishOptions(SYSTEM, await options(c.director, c.g), fx.token);
  c.g.castVote(user('w0'), 1); c.clock.advance(20_000); c.g.tick();
  const gained = c.g.s.participants['w0']!.score - afterFirst;
  assert.ok(gained <= 25, `gained ${gained}`);   // at most the "called it" bonus, never a second participation award
  void first;
});

test('the Safety Stop works from every attempt state, scores nothing and never punishes', async () => {
  for (const reach of ['ready', 'generation', 'vote', 'review', 'live', 'submission'] as const) {
    const c = setup(); c.g.s.participants['host']!.streak = 3;
    if (reach === 'ready') c.g.startRun(user('host'));
    if (reach === 'generation') { c.g.startRun(user('host')); c.g.playerReady(user('host'), {}); }
    if (reach === 'vote') await toVote(c);
    if (reach === 'review') { await toVote(c); c.g.castVote(user('w0'), 0); c.clock.advance(20_000); c.g.tick(); }
    if (reach === 'live') await toLive(c);
    if (reach === 'submission') { await toLive(c); c.g.finish(user('host')); }
    const r = c.g.safetyStop(user('host'));
    assert.equal(r.ok, true, reach);
    assert.equal(c.g.s.phase, 'ROUND_RESULT', reach);
    assert.equal(c.g.s.round!.result!.outcome, 'safety_stop');
    assert.equal(c.g.s.round!.result!.playerPoints, 0);
    assert.equal(c.g.s.participants['host']!.streak, 3, `streak kept (${reach})`);
  }
});

test('a stale generation result is refused after a Safety Stop', async () => {
  const c = setup(); c.g.startRun(user('host')); c.g.playerReady(user('host'), {});
  const fx = c.g.drain().effects.find((e) => e.type === 'generate') as any;
  c.g.safetyStop(user('host'));
  assert.equal((c.g.publishOptions(SYSTEM, await options(c.director, c.g), fx.token) as any).code, 'stale');
});

test('the Player cannot be forced forward: no accept means an automatic pass, not a forced attempt', async () => {
  const c = setup(); await toVote(c);
  c.g.castVote(user('w0'), 0); c.clock.advance(20_000); c.g.tick();
  c.clock.advance(20_000); c.g.tick();
  assert.equal(c.g.s.phase, 'CHALLENGE_GENERATION');
  assert.equal(c.g.s.round!.passes, 1);
});

// ---------- unvalidated content never reaches the vote ----------

test('the engine re-validates options: an unsafe or boundary-violating option is never published', async () => {
  const c = setup(); c.g.startRun(user('host')); c.g.playerReady(user('host'), { excludedCategories: ['perform'] });
  const fx = c.g.drain().effects.find((e) => e.type === 'generate') as any;
  assert.deepEqual(fx.boundaries.excludedCategories, ['perform']);
  const good = await options(c.director, c.g);
  const bad = structuredClone(good); bad[2]!.objective = 'Jump off the roof of your building while filming it.';
  assert.equal((c.g.publishOptions(SYSTEM, bad, fx.token) as any).code, 'unapproved_challenge');
  const wrongCat = structuredClone(good); wrongCat[0]!.category = 'perform';
  assert.equal((c.g.publishOptions(SYSTEM, wrongCat, fx.token) as any).code, 'unapproved_challenge');
  assert.equal((c.g.publishOptions(SYSTEM, good.slice(0, 4), fx.token) as any).code, 'invalid');
  assert.equal(c.g.s.phase, 'CHALLENGE_GENERATION');
  assert.equal(c.g.publishOptions(SYSTEM, good, fx.token).ok, true);
});

test('generation that never answers triggers one fallback request, then returns to the lobby', async () => {
  const c = setup(); c.g.startRun(user('host')); c.g.playerReady(user('host'), {}); c.g.drain();
  c.clock.advance(20_000); c.g.tick();
  const fx = c.g.drain().effects.filter((e) => e.type === 'generate') as any[];
  assert.equal(fx.length, 1); assert.equal(fx[0].forceFallback, true);
  c.clock.advance(10_000); c.g.tick();
  assert.equal(c.g.s.phase, 'LOBBY');
});

// ---------- reconnect, disconnect, snapshots ----------

test('a disconnected client can restore the current authoritative state from a snapshot', async () => {
  const c = setup(); await toVote(c);
  c.g.castVote(user('w0'), 3);
  c.g.setPresence('w0', false);
  const before = (await import('../src/engine/view.ts')).viewFor(c.g.s, 'w0', c.clock.now());
  c.g.join(user('w0'), { handle: 'w0', avatar: 'fox' });                   // reconnect
  const after = (await import('../src/engine/view.ts')).viewFor(c.g.s, 'w0', c.clock.now());
  assert.equal(after.phase, 'CHALLENGE_VOTE'); assert.equal(after.you!.vote, 3); assert.equal(after.round!.options.length, 5);
  assert.ok(after.rev > before.rev);
  // other people's votes never appear in anyone's view
  const other = (await import('../src/engine/view.ts')).viewFor(c.g.s, 'w1', c.clock.now());
  assert.equal(other.you!.vote, null);
  assert.equal(JSON.stringify(other).includes('"votes"'), false);
});

test('snapshot -> restore round-trips and keeps working (server restart)', async () => {
  const c = setup(); await toVote(c); c.g.castVote(user('w0'), 2);
  const restored = GameSession.restore(c.g.snapshot(), c.deps);
  restored.castVote(user('w1'), 2);
  c.clock.advance(20_000); restored.tick();
  assert.equal(restored.s.round!.chosenIdx, 2);
  assert.equal(restored.s.phase, 'PLAYER_REVIEW');
});

test('a Player who disconnects mid-attempt gets a grace period, then the round is abandoned without penalty', async () => {
  const c = setup(); await toLive(c);
  c.g.s.participants['host']!.streak = 2;
  c.g.setPresence('host', false);
  c.clock.advance(10_000); c.g.tick();
  assert.equal(c.g.s.phase, 'LIVE_ROUND');                                  // still inside the grace period
  c.g.join(user('host'), { handle: 'host', avatar: 'a01' });              // back in time
  assert.equal(c.g.s.playerGraceUntil, null);
  c.g.setPresence('host', false);
  c.clock.advance(21_000); c.g.tick();
  assert.equal(c.g.s.round!.result!.outcome, 'abandoned');
  assert.equal(c.g.s.participants['host']!.streak, 2);
  assert.equal(c.g.s.playerId, null);
});

// ---------- THE TWIST ----------

test('THE TWIST opens mid-round, is voted on, and is applied from approved templates only', async () => {
  const c = setup(); const { opts } = await toLive(c);
  const open = c.g.s.round!.twist;
  if (!open) return;                                  // the chosen dare may allow no compatible twist
  c.clock.advance(Math.round(opts[0]!.durationSeconds * 1000 * 0.4) + 1); c.g.tick();
  assert.equal(c.g.s.round!.twist!.status, 'open');
  c.g.castTwistVote(user('w0'), 1); c.g.castTwistVote(user('w1'), 1); c.g.castTwistVote(user('w2'), 0);
  assert.equal((c.g.castTwistVote(user('host'), 0) as any).code, 'forbidden');
  c.clock.advance(8_001); c.g.tick();
  assert.equal(c.g.s.round!.twist!.status, 'closed');
  assert.equal(c.g.s.round!.twist!.applied!.id, open.options[1]!.id);
  assert.equal(c.g.s.round!.deadline! - c.g.s.round!.startedAt!, opts[0]!.durationSeconds * 1000);   // twist never changes the clock
});

// ---------- moderation precedence ----------

test('moderator stream cut ends the attempt through the safety path and blocks continuing; clients cannot do it', async () => {
  const c = setup(); await toLive(c);
  assert.equal((c.g.modCutStream(user('host')) as any).code, 'forbidden');
  assert.equal(c.g.modCutStream(MOD).ok, true);
  assert.equal(c.g.s.round!.result!.outcome, 'moderated');
  assert.equal(c.g.drain().effects.some((e) => e.type === 'cut_stream'), true);
  assert.equal((c.g.next(user('host')) as any).code, 'stream_cut');
  assert.equal(c.g.modEnd(MOD).ok, true);
  assert.equal(c.g.s.phase, 'SESSION_END');
  assert.equal((c.g.join(user('late'), { handle: 'l', avatar: 'x' }) as any).code, 'ended');
});

test('kicked users are banned from rejoining', () => {
  const c = setup();
  c.g.modKick(MOD, 'w1');
  assert.equal(c.g.s.participants['w1'], undefined);
  assert.equal((c.g.join(user('w1'), { handle: 'w1', avatar: 'x' }) as any).code, 'banned');
});

// ---------- stage hand-off ----------

test('a watcher can request the stage and receives it between rounds', async () => {
  const c = setup(); await toLive(c);
  c.g.requestStage(user('w1'));
  c.g.finish(user('host')); c.g.submit(user('host')); c.clock.advance(15_000); c.g.tick();
  assert.equal(c.g.s.phase, 'ROUND_RESULT');
  assert.equal((c.g.handoff(user('w0'), 'w1') as any).code, 'forbidden');
  assert.equal(c.g.handoff(user('host')).ok, true);
  assert.equal(c.g.s.playerId, 'w1'); assert.equal(c.g.s.participants['w1']!.role, 'player');
  assert.equal(c.g.s.participants['host']!.role, 'watcher');
  assert.equal(c.g.s.phase, 'LOBBY');
});
