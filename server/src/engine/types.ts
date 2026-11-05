import type { Boundaries, Challenge, Difficulty, Modifier, ModifierId } from '../policy/types.ts';

export const PHASES = [
  'LOBBY', 'READY_CHECK', 'CHALLENGE_GENERATION', 'CHALLENGE_VOTE', 'PLAYER_REVIEW',
  'LIVE_ROUND', 'SUBMISSION', 'AUDIENCE_VERDICT', 'ROUND_RESULT', 'SESSION_END',
] as const;
export type Phase = (typeof PHASES)[number];

export type Role = 'player' | 'watcher';

/** Who is issuing a command. Only the server runtime may act as `system`; clients can only ever be `user`. */
export type Actor = { kind: 'user'; id: string } | { kind: 'system' } | { kind: 'moderator'; id: string };

export type ErrorCode =
  | 'forbidden' | 'bad_phase' | 'not_found' | 'invalid' | 'banned' | 'full'
  | 'vote_closed' | 'already_voted' | 'unapproved_challenge' | 'stale' | 'no_candidate' | 'stream_cut' | 'ended';

export type EngineResult<T extends object = object> = ({ ok: true } & T) | { ok: false; code: ErrorCode; message: string };

export type Outcome = 'completed' | 'failed' | 'safety_stop' | 'abandoned' | 'moderated';

export interface Timings {
  readyMs: number; generationMs: number; voteMs: number; reviewMs: number; submissionMs: number;
  verdictMs: number; resultMs: number; twistVoteMs: number; graceMs: number; fallbackWaitMs: number;
}

export interface SessionConfig {
  title: string;
  hostId: string;
  /** Who this session is for. Set from the host's age band when the session is created; teens and adults never share a session. Missing on very old snapshots = adult. */
  band?: 'teen' | 'adult';
  twist: boolean;
  maxWatchers: number;
  startDifficulty: Difficulty;
  timings: Timings;
}

export interface Participant {
  id: string; handle: string; avatar: string; role: Role; joinedAt: number; online: boolean;
  score: number; streak: number; roundsPlayed: number; roundsCompleted: number; votesCast: number; calledIt: number;
}

export interface TwistState {
  status: 'pending' | 'open' | 'closed';
  options: Modifier[];
  votes: Record<string, number>;
  voteAt: Record<string, number>;
  opensAt: number;
  closesAt: number;
  applied: Modifier | null;
}

export interface RoundResult {
  round: number; playerId: string; playerHandle: string;
  challengeId: string | null; challengeTitle: string | null; difficulty: number | null;
  outcome: Outcome; judged: boolean; yes: number; no: number;
  playerPoints: number; streak: number; awards: Record<string, number>; passes: number;
  twist: ModifierId | null; at: number;
}

export interface Round {
  n: number;
  options: Challenge[];
  votes: Record<string, number>;
  voteAt: Record<string, number>;
  voteAwarded: Record<string, true>;
  chosenIdx: number | null;
  chosenBy: 'vote' | 'no_votes' | null;
  finalTally: number[] | null;
  passes: number;
  startedAt: number | null;
  deadline: number | null;
  endedAt: number | null;
  twist: TwistState | null;
  note: string | null;
  verdicts: Record<string, boolean>;
  verdictClosed: boolean;
  awards: Record<string, number>;
  result: RoundResult | null;
}

export interface EngineState {
  id: string; code: string; config: SessionConfig; phase: Phase; rev: number;
  createdAt: number; phaseStartedAt: number; phaseDeadline: number | null;
  participants: Record<string, Participant>;
  queue: string[]; banned: string[];
  playerId: string | null; boundaries: Boundaries;
  roundNumber: number; completedCount: number; recentTitles: string[];
  round: Round | null; history: RoundResult[];
  playerGraceUntil: number | null;
  generation: { token: number; attempts: number };
  streamCut: boolean; endedReason: string | null;
}

export type Effect =
  | { type: 'generate'; token: number; round: number; difficulty: Difficulty; boundaries: Boundaries; recentTitles: string[]; forceFallback: boolean }
  | { type: 'cut_stream'; playerId: string };

export interface EngineEvent { rev: number; type: string; data: Record<string, unknown> }

export interface EngineDeps {
  now: () => number;
  rng: () => number;
  uid: () => string;
  /** Re-validates a challenge against the Player's boundaries. The engine never trusts the caller's word that an option is approved. */
  approve: (c: Challenge, b: Boundaries) => boolean;
}
