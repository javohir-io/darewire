import { randomInt } from 'node:crypto';
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
export function roomCode(len = 6): string {
  let s = '';
  for (let i = 0; i < len; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}
/** The 12 built-in avatars: a01 ... a12 (images live in the app's assets). */
export const AVATARS: readonly string[] = Array.from({ length: 12 }, (_, i) => `a${String(i + 1).padStart(2, '0')}`);
export const DEFAULT_AVATAR = 'a01';
/** Custom (gallery) avatars are served from this API path. Only the server ever writes it; clients cannot set it directly. */
export const customAvatarPath = (userId: string, version: number) => `/v1/avatars/${userId}?v=${version}`;
export const isCustomAvatar = (v: string) => /^\/v1\/avatars\/[A-Za-z0-9_-]{3,64}\?v=\d{1,16}$/.test(v);
export const HANDLE_RE = /^[a-z0-9_]{3,20}$/;
export function ageFrom(birthDate: string, today = new Date()): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birthDate);
  if (!m) return null;
  const y = +m[1]!, mo = +m[2]!, d = +m[3]!;
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d || dt > today || y < 1900) return null;
  let age = today.getUTCFullYear() - y;
  if (today.getUTCMonth() + 1 < mo || (today.getUTCMonth() + 1 === mo && today.getUTCDate() < d)) age--;
  return age;
}
