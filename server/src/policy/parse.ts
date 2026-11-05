// Structural validation of an untrusted challenge candidate (AI output is untrusted input).
import {
  CATEGORIES, MODIFIER_IDS, SCORING_TYPES, THEMES,
  type Category, type ChallengeDraft, type Difficulty, type ModifierId, type ScoringType, type Theme,
} from './types.ts';

export type ParseResult = { ok: true; value: ChallengeDraft } | { ok: false; errors: string[] };

const ZERO_WIDTH = /[\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]/g;
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;

/** NFKC-normalise, strip invisible characters and collapse whitespace. */
export function cleanText(s: string): string {
  return s.normalize('NFKC').replace(ZERO_WIDTH, '').replace(/\s+/g, ' ').trim();
}

function str(v: unknown, field: string, min: number, max: number, errors: string[]): string {
  if (typeof v !== 'string') { errors.push(`${field}: must be a string`); return ''; }
  if (CONTROL.test(v)) errors.push(`${field}: contains control characters`);
  const t = cleanText(v);
  if (t.length < min || t.length > max) errors.push(`${field}: length must be ${min}-${max}`);
  return t;
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[], field: string, errors: string[]): T | null {
  if (typeof v !== 'string') { errors.push(`${field}: must be a string`); return null; }
  const n = v.trim().toLowerCase().replace(/[\s-]+/g, '_');
  if ((allowed as readonly string[]).includes(n)) return n as T;
  errors.push(`${field}: unknown value`);
  return null;
}

function list<T extends string>(v: unknown, allowed: readonly T[], field: string, max: number, errors: string[]): T[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) { errors.push(`${field}: must be an array`); return []; }
  if (v.length > max) errors.push(`${field}: at most ${max} items`);
  const out: T[] = [];
  for (const item of v) {
    const x = oneOf(item, allowed, field, errors);
    if (x && !out.includes(x)) out.push(x);
  }
  return out;
}

export function parseCandidate(raw: unknown): ParseResult {
  const errors: string[] = [];
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { ok: false, errors: ['candidate: must be an object'] };
  const r = raw as Record<string, unknown>;

  const category = oneOf(r.category, CATEGORIES, 'category', errors) as Category | null;
  const title = str(r.title, 'title', 3, 48, errors);
  const objective = str(r.objective, 'objective', 12, 220, errors);

  const dur = r.durationSeconds;
  if (typeof dur !== 'number' || !Number.isInteger(dur) || dur < 20 || dur > 180) errors.push('durationSeconds: integer 20-180');
  const diff = r.difficulty;
  if (typeof diff !== 'number' || !Number.isInteger(diff) || diff < 1 || diff > 5) errors.push('difficulty: integer 1-5');

  const criteriaRaw = r.completionCriteria;
  const criteria: string[] = [];
  if (!Array.isArray(criteriaRaw) || criteriaRaw.length < 1 || criteriaRaw.length > 4) errors.push('completionCriteria: 1-4 items');
  else for (const c of criteriaRaw) criteria.push(str(c, 'completionCriteria[]', 6, 120, errors));

  const allowedModifiers = list<ModifierId>(r.allowedModifiers, MODIFIER_IDS, 'allowedModifiers', 4, errors);
  const scoringType = (r.scoringType === undefined ? 'audience_judgment' : oneOf(r.scoringType, SCORING_TYPES, 'scoringType', errors)) as ScoringType | null;
  const tags = list<Theme>(r.tags, THEMES, 'tags', 4, errors);

  if (errors.length || !category || !scoringType) return { ok: false, errors: errors.length ? errors : ['candidate: invalid'] };
  return {
    ok: true,
    value: {
      category, title, objective,
      durationSeconds: dur as number, difficulty: diff as Difficulty,
      completionCriteria: criteria, allowedModifiers, scoringType, tags,
    },
  };
}
