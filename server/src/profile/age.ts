// Age bands. DAREWIRE is for people aged 16 and over.
//
//   16-17  "teen"   Teen accounts: dares are held to a stricter content floor, and teens only share live sessions, duels and
//                   search with other teens (adults and teens never reach each other).
//   18+    "adult"  Everything else.
//
// The band is derived from the stored date of birth on every request, so a teen becomes an adult automatically on their 18th
// birthday and nothing needs a migration. Moderators and admins are "staff": they may see both bands so they can moderate.
// Age is self-declared (a screen, not identity verification). See docs/threat-model.md.
import type { Profile } from '../store/types.ts';
import { ageFrom } from '../util/ids.ts';

/** Youngest allowed account. Change this one number to move the age floor (and update the copy in the app). */
export const MIN_AGE = 16;
/** From this age on an account is an adult account. */
export const ADULT_AGE = 18;

export type AgeBand = 'teen' | 'adult';

export function bandForAge(age: number | null): AgeBand | null {
  if (age === null || age < MIN_AGE) return null;
  return age >= ADULT_AGE ? 'adult' : 'teen';
}

export const isStaff = (p: Pick<Profile, 'role'>): boolean => p.role !== 'user';

/** The band of an account, from its date of birth. Null until the age gate is passed. Staff report the band of their birth date too (or 'adult'). */
export function bandOf(p: Pick<Profile, 'birthDate' | 'role'>, today = new Date()): AgeBand | null {
  const b = p.birthDate ? bandForAge(ageFrom(p.birthDate, today)) : null;
  return b ?? (isStaff(p) ? 'adult' : null);
}

/** May these two accounts see and reach each other? Same band, or either side is staff. Accounts without a profile (demo content) are open to all. */
export function sameBand(viewer: Pick<Profile, 'birthDate' | 'role'>, other: Pick<Profile, 'birthDate' | 'role'> | null | undefined, today = new Date()): boolean {
  if (!other) return true;
  if (isStaff(viewer) || isStaff(other)) return true;
  const a = bandOf(viewer, today), b = bandOf(other, today);
  return a !== null && a === b;
}
