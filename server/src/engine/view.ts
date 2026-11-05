// Per-user projection of the authoritative state. Clients only ever receive this, never the raw state:
// other people's votes, verdicts and hidden fields are not in it.
import type { Challenge, Modifier } from '../policy/types.ts';
import type { EngineState, Participant, RoundResult } from './types.ts';

export interface PublicParticipant { id: string; handle: string; avatar: string; role: string; score: number; streak: number; online: boolean }

export interface SessionView {
  id: string; code: string; title: string; phase: string; rev: number; serverTime: number;
  phaseStartedAt: number; phaseDeadline: number | null; roundNumber: number; hostId: string; twistEnabled: boolean; streamCut: boolean;
  endedReason: string | null;
  you: null | { id: string; role: string; isHost: boolean; vote: number | null; verdict: boolean | null; twistVote: number | null; queued: boolean };
  player: PublicParticipant | null;
  watcherCount: number;
  roster: PublicParticipant[];
  queue: PublicParticipant[];
  boundaries: { excludedCategories: string[]; excludedThemes: string[]; maxDifficulty: number; teen: boolean };
  band: 'teen' | 'adult';
  round: null | {
    n: number; options: Challenge[]; tally: number[] | null; totalVotes: number; chosenIdx: number | null; chosenBy: string | null;
    passes: number; startedAt: number | null; deadline: number | null; note: string | null;
    twist: null | { status: string; options: Modifier[]; tally: number[]; opensAt: number; closesAt: number; applied: Modifier | null };
    verdict: { cast: number; yes: number | null; no: number | null };
    result: RoundResult | null;
  };
  history: RoundResult[];
}

const pub = (p: Participant): PublicParticipant => ({ id: p.id, handle: p.handle, avatar: p.avatar, role: p.role, score: p.score, streak: p.streak, online: p.online });

export function viewFor(s: EngineState, userId: string | null, now: number): SessionView {
  const me = userId ? s.participants[userId] : undefined;
  const all = Object.values(s.participants);
  const r = s.round;
  const showOptions = r && r.options.length > 0 && s.phase !== 'CHALLENGE_GENERATION';
  let tally: number[] | null = null;
  if (r && showOptions) {
    tally = r.finalTally ? [...r.finalTally] : (() => { const t = new Array<number>(r.options.length).fill(0); for (const i of Object.values(r.votes)) t[i]!++; return t; })();
  }
  const tw = r?.twist ?? null;
  const verdictVals = r ? Object.values(r.verdicts) : [];
  return {
    id: s.id, code: s.code, title: s.config.title, phase: s.phase, rev: s.rev, serverTime: now,
    phaseStartedAt: s.phaseStartedAt, phaseDeadline: s.phaseDeadline, roundNumber: s.roundNumber, hostId: s.config.hostId,
    twistEnabled: s.config.twist, streamCut: s.streamCut, endedReason: s.endedReason,
    you: me ? {
      id: me.id, role: me.role, isHost: me.id === s.config.hostId,
      vote: r?.votes[me.id] ?? null, verdict: r?.verdicts[me.id] ?? null, twistVote: tw?.votes[me.id] ?? null, queued: s.queue.includes(me.id),
    } : null,
    player: s.playerId && s.participants[s.playerId] ? pub(s.participants[s.playerId]!) : null,
    watcherCount: all.filter((p) => p.role === 'watcher').length,
    roster: [...all].sort((a, b) => b.score - a.score).slice(0, 12).map(pub),
    queue: s.queue.slice(0, 10).map((id) => s.participants[id]).filter((p): p is Participant => !!p).map(pub),
    boundaries: { excludedCategories: s.boundaries.excludedCategories, excludedThemes: s.boundaries.excludedThemes, maxDifficulty: s.boundaries.maxDifficulty, teen: s.boundaries.audience === 'teen' },
    band: s.config.band ?? 'adult',
    round: r ? {
      n: r.n, options: showOptions ? r.options : [], tally, totalVotes: Object.keys(r.votes).length,
      chosenIdx: r.chosenIdx, chosenBy: r.chosenBy, passes: r.passes, startedAt: r.startedAt, deadline: r.deadline, note: r.note,
      twist: tw && tw.status !== 'pending' ? {
        status: tw.status, options: tw.options, opensAt: tw.opensAt, closesAt: tw.closesAt, applied: tw.applied,
        tally: tw.options.map((_, i) => Object.values(tw.votes).filter((v) => v === i).length),
      } : null,
      verdict: {
        cast: verdictVals.length,
        yes: r.verdictClosed ? verdictVals.filter(Boolean).length : null,
        no: r.verdictClosed ? verdictVals.filter((v) => !v).length : null,
      },
      result: r.result,
    } : null,
    history: s.history.slice(-5),
  };
}
