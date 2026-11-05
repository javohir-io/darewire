// Shared domain types for challenges and boundaries. Pure data: no I/O, no dependencies.

export const CATEGORIES = ['improvise', 'create', 'perform', 'solve', 'social_courage'] as const;
export type Category = (typeof CATEGORIES)[number];

// Themes a Player can exclude. Enumerated on purpose: boundaries are never free text,
// so they cannot be used to smuggle instructions into a prompt.
export const THEMES = [
  'singing', 'dancing', 'romance', 'food_props', 'accents', 'public_speaking',
  'dark_humor', 'physical_comedy', 'role_play', 'trivia_pressure',
] as const;
export type Theme = (typeof THEMES)[number];

export const MODIFIER_IDS = [
  'change_the_tone', 'add_a_required_word', 'whisper_only', 'third_person', 'rhyme',
  'new_character', 'slow_motion_voice', 'dramatic_pause', 'sports_commentator',
] as const;
export type ModifierId = (typeof MODIFIER_IDS)[number];

export const SCORING_TYPES = ['audience_judgment', 'objective_check'] as const;
export type ScoringType = (typeof SCORING_TYPES)[number];

export type Difficulty = 1 | 2 | 3 | 4 | 5;

/** Schema version of the challenge object. Bump when fields change. */
export const CHALLENGE_SCHEMA_VERSION = 1;

export interface ChallengeDraft {
  category: Category;
  title: string;
  objective: string;
  durationSeconds: number;
  difficulty: Difficulty;
  completionCriteria: string[];
  allowedModifiers: ModifierId[];
  scoringType: ScoringType;
  tags: Theme[];
}

export interface Challenge extends ChallengeDraft {
  id: string;
  origin: 'ai' | 'fallback';
  schemaVersion: number;
}

/** Who the dares are for. Teen sessions (all players aged 16-17) get a stricter content floor than adult sessions. */
export type Audience = 'teen' | 'adult';

export interface Boundaries {
  excludedCategories: Category[];
  excludedThemes: Theme[];
  maxDifficulty: Difficulty;
  /** Set by the SERVER (never read from a client) when the dares are for teens. `sanitizeBoundaries` drops it on purpose. */
  audience?: Audience;
}

/** The teen content floor. Players can add boundaries on top of these but can never remove them. */
export const TEEN_FLOOR = {
  excludedCategories: ['social_courage'] as readonly Category[],   // dares that involve approaching other people
  excludedThemes: ['romance', 'dark_humor'] as readonly Theme[],
  maxDifficulty: 3 as Difficulty,                                     // levels 4 and 5 carry the most pressure
};

export const DEFAULT_BOUNDARIES: Boundaries = {
  excludedCategories: [],
  excludedThemes: [],
  maxDifficulty: 5,
};

export interface Modifier {
  id: ModifierId;
  text: string;
}

/** Normalise untrusted boundaries (from a client or the database) into a safe, complete object. */
export function sanitizeBoundaries(raw: unknown): Boundaries {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const pick = <T extends string>(v: unknown, allowed: readonly T[]): T[] =>
    Array.isArray(v) ? [...new Set(v.filter((x): x is T => typeof x === 'string' && (allowed as readonly string[]).includes(x)))] : [];
  const md = Number(r.maxDifficulty);
  const maxDifficulty = (Number.isInteger(md) && md >= 1 && md <= 5 ? md : 5) as Difficulty;
  return {
    excludedCategories: pick(r.excludedCategories, CATEGORIES),
    excludedThemes: pick(r.excludedThemes, THEMES),
    maxDifficulty,
  };
}

/**
 * Applies the audience to a player's own boundaries. For teens this adds the floor (union of exclusions, lower difficulty cap)
 * and marks the result so `checkPolicy` also applies the teen word rules. For adults the boundaries are returned unchanged.
 */
export function withAudience(b: Boundaries, audience: Audience | null | undefined): Boundaries {
  const base: Boundaries = { excludedCategories: [...b.excludedCategories], excludedThemes: [...b.excludedThemes], maxDifficulty: b.maxDifficulty };
  if (audience !== 'teen') return base;
  return {
    excludedCategories: [...new Set([...base.excludedCategories, ...TEEN_FLOOR.excludedCategories])],
    excludedThemes: [...new Set([...base.excludedThemes, ...TEEN_FLOOR.excludedThemes])],
    maxDifficulty: Math.min(base.maxDifficulty, TEEN_FLOOR.maxDifficulty) as Difficulty,
    audience: 'teen',
  };
}
