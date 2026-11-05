import { GameSession } from '../src/engine/index.ts';
import type { Actor, EngineDeps, Timings } from '../src/engine/index.ts';
import { Director } from '../src/director/director.ts';
import { approveChallenge } from '../src/director/approve.ts';
import type { Challenge } from '../src/policy/types.ts';

export class Clock {
  t = 1_000_000;
  now = () => this.t;
  advance(ms: number) { this.t += ms; }
}

/** Small deterministic PRNG so tests never depend on Math.random. */
export function seeded(seed = 7) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 2 ** 32; };
}

export const user = (id: string): Actor => ({ kind: 'user', id });
export const SYSTEM: Actor = { kind: 'system' };
export const MOD: Actor = { kind: 'moderator', id: 'mod1' };

export function setup(opts: { twist?: boolean; timings?: Partial<Timings>; watchers?: number } = {}) {
  const clock = new Clock();
  let n = 0;
  const deps: EngineDeps = { now: clock.now, rng: seeded(), uid: () => `id${++n}`, approve: approveChallenge };
  const g = GameSession.create({ id: 's1', code: 'ABC123', title: 'Test', hostId: 'host', twist: opts.twist ?? true, timings: opts.timings }, deps);
  g.join(user('host'), { handle: 'host', avatar: 'a01' }, 'player');
  const watchers: string[] = [];
  for (let i = 0; i < (opts.watchers ?? 3); i++) { const id = `w${i}`; g.join(user(id), { handle: id, avatar: 'a02' }); watchers.push(id); }
  const director = new Director({ llm: null, review: false, rng: seeded(3), uid: () => `c${++n}` });
  return { g, clock, deps, director, watchers };
}

export async function options(director: Director, g: GameSession): Promise<Challenge[]> {
  const r = await director.generate({ difficulty: 2, boundaries: g.s.boundaries, recentTitles: [] });
  return r.options;
}

/** Drive a session to CHALLENGE_VOTE. Returns the effect token used. */
export async function toVote(ctx: ReturnType<typeof setup>) {
  const { g, director } = ctx;
  g.startRun(user('host'));
  g.playerReady(user('host'), {});
  const fx = g.drain().effects.find((e) => e.type === 'generate');
  if (!fx || fx.type !== 'generate') throw new Error('no generate effect');
  const opts = await options(director, g);
  const res = g.publishOptions(SYSTEM, opts, fx.token);
  if (!res.ok) throw new Error('publish failed: ' + res.message);
  return { token: fx.token, opts };
}

/** Drive to LIVE_ROUND with the given watchers voting for option 0. */
export async function toLive(ctx: ReturnType<typeof setup>) {
  const r = await toVote(ctx);
  for (const w of ctx.watchers) ctx.g.castVote(user(w), 0);
  ctx.clock.advance(21_000); ctx.g.tick();
  const res = ctx.g.accept(user('host'));
  if (!res.ok) throw new Error('accept failed: ' + res.message);
  return r;
}
