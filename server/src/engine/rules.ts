// Published game rules: timings, scoring and the voting tie-break. Mirrored in docs/game-rules.md.
import type { Timings } from './types.ts';

export const DEFAULT_TIMINGS: Timings = {
  readyMs: 60_000, generationMs: 20_000, voteMs: 20_000, reviewMs: 20_000, submissionMs: 15_000,
  verdictMs: 15_000, resultMs: 45_000, twistVoteMs: 8_000, graceMs: 20_000, fallbackWaitMs: 10_000,
};

export const POINTS = {
  perDifficulty: 100,   // Player: completed attempt = 100 x difficulty
  streakStep: 25,       // Player: + 25 per consecutive completed round (before this one)
  streakCap: 4,
  unjudgedFactor: 0.5,  // nobody judged the attempt: half points, never zero
  vote: 10,             // Watcher: took part in the dare vote (once per round, even if the Player passes)
  calledIt: 25,         // Watcher: voted for the dare that won
  verdictMatch: 10,     // Watcher: verdict matched the majority
  twistMatch: 10,       // Watcher: voted for the twist that was applied
} as const;

export const MIN_EARLY_LOCK_MS = 5_000;
export const HISTORY_LIMIT = 50;
export const RECENT_TITLES = 20;
export const NOTE_MAX = 280;

export function playerPoints(difficulty: number, streakBefore: number, judged: boolean): number {
  const base = POINTS.perDifficulty * difficulty + POINTS.streakStep * Math.min(streakBefore, POINTS.streakCap);
  return judged ? base : Math.round(base * POINTS.unjudgedFactor);
}

/**
 * Plurality wins. A tie goes to the option whose final vote arrived earliest (it "reached the tie first").
 * No votes at all: the server picks at random (recorded as `no_votes`). Pure and deterministic given the inputs.
 */
export function pickWinner(
  votes: Record<string, number>, voteAt: Record<string, number>, optionCount: number, rng: () => number,
): { idx: number; tally: number[]; by: 'vote' | 'no_votes' } {
  const tally = new Array<number>(optionCount).fill(0);
  const lastAt = new Array<number>(optionCount).fill(0);
  for (const [uid, idx] of Object.entries(votes)) {
    tally[idx]!++;
    lastAt[idx] = Math.max(lastAt[idx]!, voteAt[uid] ?? 0);
  }
  const max = Math.max(...tally);
  if (max === 0) return { idx: Math.floor(rng() * optionCount), tally, by: 'no_votes' };
  let best = -1;
  for (let i = 0; i < optionCount; i++) {
    if (tally[i] !== max) continue;
    if (best === -1 || lastAt[i]! < lastAt[best]!) best = i;
  }
  return { idx: best, tally, by: 'vote' };
}
