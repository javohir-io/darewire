import type { Profile, UserStats } from '../store/types.ts';

export interface Badge { id: string; label: string; desc: string }

/** Badges are derived from stats on the server, so they cannot be faked by a client. */
export function badgesFor(stats: UserStats, profile: Pick<Profile, 'role'>): Badge[] {
  const out: Badge[] = [];
  if (profile.role !== 'user') out.push({ id: 'warden', label: 'Moderator', desc: 'Helps keep DAREWIRE safe' });
  if (stats.completed >= 1) out.push({ id: 'first_blood', label: 'First Dare', desc: 'Completed a first dare' });
  if (stats.bestStreak >= 3) out.push({ id: 'on_fire', label: 'On Fire', desc: 'A streak of 3 completed dares' });
  if (stats.bestStreak >= 5) out.push({ id: 'unstoppable', label: 'Unstoppable', desc: 'A streak of 5 or more' });
  if (stats.rounds >= 25) out.push({ id: 'veteran', label: 'Veteran', desc: '25 rounds on stage' });
  if (stats.points >= 5000) out.push({ id: 'high_roller', label: 'High Roller', desc: '5,000 points earned' });
  if (stats.clips >= 1) out.push({ id: 'clipper', label: 'Clipper', desc: 'Posted a dare video' });
  if (stats.duels >= 1) out.push({ id: 'duelist', label: 'Duelist', desc: 'Completed a duel' });
  if (stats.likes >= 25) out.push({ id: 'crowd_favorite', label: 'Crowd Favorite', desc: '25 likes on clips' });
  return out;
}

export const ACCENTS = ['neon', 'pink', 'lime', 'blue', 'violet', 'aqua', 'coral'] as const;
