// What may be sent in a direct message. A deliberately small, explainable filter, not a promise that nothing bad gets through:
// reporting, blocking and moderation are the real safety net (see docs/threat-model.md).
//
// For everyone: no contact details or links (they are how scams, grooming and off-platform moves start) and no explicit or threatening content.
// For teens, also: no personal questions, no "meet up" talk, no asking to move to another app, and no "keep it secret".
import { cleanText } from '../policy/parse.ts';

export const MAX_MESSAGE_LENGTH = 500;

export type MessageVerdict = { ok: true; text: string } | { ok: false; reason: 'empty' | 'too_long' | 'contact_details' | 'unsafe' | 'personal_questions'; message: string };

const CONTACT: RegExp[] = [
  /\bhttps?:\/\//i, /\bwww\./i,
  /\b[\w-]+\.(?:com|net|org|io|me|gg|app|ly|tv|co|xyz|link|to)\b/i,
  /[\w.+-]+@[\w-]+\.[\w.]+/,                                   // email
  /(?:\+?\d[\s().-]?){8,}/,                                      // a phone number (8 or more digits, however it is spaced)
  /(?:^|\s)@[a-z0-9_.]{3,}\b/i,                                  // an @handle (another platform's)
];
const UNSAFE = /\b(?:kill yourself|kys|i(?:'| wi)?ll (?:kill|hurt|find) you|nudes?|sext\w*|naked|send (?:me )?(?:a )?(?:sexy|nsfw)\b|n[i1]gg\w*|f[a4]gg?[o0]t\w*|retard\w*)\b/i;
const TEEN_ONLY = /\b(?:meet (?:me|up|you)|come (?:over|to my)|where (?:do|are) you (?:live|from)|what school|which school|how old are you|home alone|send (?:me )?(?:a )?(?:pic|picture|photo|selfie)s?|our little secret|(?:don'?t|do not) tell (?:your|anyone|ur)|keep (?:it|this) (?:a )?secret|snap(?:chat)?|insta(?:gram)?|whats ?app|telegram|discord|kik|tiktok|facetime|video call)\b/i;

export function moderateMessage(raw: unknown, teen: boolean): MessageVerdict {
  const text = typeof raw === 'string' ? cleanText(raw) : '';
  if (!text) return { ok: false, reason: 'empty', message: 'Write a message first' };
  if (text.length > MAX_MESSAGE_LENGTH) return { ok: false, reason: 'too_long', message: `Messages can be up to ${MAX_MESSAGE_LENGTH} characters` };
  if (UNSAFE.test(text)) return { ok: false, reason: 'unsafe', message: 'That message cannot be sent. Please keep chats kind and appropriate.' };
  if (CONTACT.some((r) => r.test(text))) return { ok: false, reason: 'contact_details', message: 'Please do not share links, numbers or contact details in chat.' };
  if (teen && TEEN_ONLY.test(text)) return { ok: false, reason: 'personal_questions', message: 'That message cannot be sent. On DAREWIRE we do not share personal details, arrange to meet, or move chats to other apps.' };
  return { ok: true, text };
}
