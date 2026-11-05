import { parseCandidate } from '../policy/parse.ts';
import { checkPolicy } from '../policy/policy.ts';
import type { Boundaries, Challenge } from '../policy/types.ts';

/** The engine's own check on anything it is asked to publish. Same code path the Director uses, re-run independently. */
export function approveChallenge(c: Challenge, b: Boundaries): boolean {
  const p = parseCandidate(c);
  return p.ok && checkPolicy(p.value, b).ok;
}
