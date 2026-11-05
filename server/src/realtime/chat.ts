import { cleanText } from '../policy/parse.ts';

export const REACTIONS = ['fire', 'clap', 'laugh', 'wow', 'heart'] as const;
export type Reaction = (typeof REACTIONS)[number];

const CONTACT = /(?:https?:|www\.|\.[a-z]{2,}\/|[a-z0-9._%+-]+@[a-z0-9.-]+|\+?\d[\d\s().-]{7,}\d)/i;

export interface ChatMsg { id: string; userId: string; handle: string; text: string; at: number }

/** Session chat is deliberately small: short, no links or contact details, rate-limited, reportable and moderator-deletable. */
export function cleanChat(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const t = cleanText(raw);
  if (t.length < 1 || t.length > 140) return null;
  if (CONTACT.test(t)) return null;
  return t;
}
