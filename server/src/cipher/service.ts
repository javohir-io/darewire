import type { LlmClient } from '../director/llm.ts';
import { cleanText } from '../policy/parse.ts';
import { log } from '../util/log.ts';
import { CRISIS_REPLY, MOODS, TONES, buildSystem, cleanCtx, isCrisis, offlineReply, parseReply, type CipherReply, type Tone } from './persona.ts';

const arr = (items: Record<string, unknown>) => ({ type: 'ARRAY', items });
const CHAT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    messages: arr({ type: 'STRING' }),
    mood: { type: 'STRING', enum: [...MOODS] },
    loyaltyDelta: { type: 'INTEGER' },
  },
  required: ['messages', 'mood', 'loyaltyDelta'],
};

export interface CipherInput { messages: unknown; loyalty?: unknown; tone?: unknown; name?: unknown; hour?: unknown; ctx?: unknown; /** Decided by the server from the account's age, never taken from the client. */ band?: 'teen' | 'adult' }

export class CipherError extends Error {
  status = 400;
  constructor(message: string) { super(message); }
}

export const MAX_TURNS = 14;
export const MAX_TEXT = 400;

/** Normalise untrusted chat history from the client: roles whitelisted, text cleaned and capped, last turn must be the user's. */
export function sanitizeHistory(raw: unknown): { role: 'user' | 'model'; text: string }[] {
  if (!Array.isArray(raw)) throw new CipherError('messages must be an array');
  const out: { role: 'user' | 'model'; text: string }[] = [];
  for (const m of raw.slice(-MAX_TURNS)) {
    const r = (m && typeof m === 'object' ? m : {}) as Record<string, unknown>;
    const text = typeof r.text === 'string' ? cleanText(r.text).slice(0, MAX_TEXT) : '';
    if (!text) continue;
    out.push({ role: r.role === 'cipher' || r.role === 'model' ? 'model' : 'user', text });
  }
  while (out.length && out[0]!.role === 'model') out.shift();     // Gemini wants the conversation to start with the user
  if (!out.length || out[out.length - 1]!.role !== 'user') throw new CipherError('The last message must be from the user');
  return out;
}

export class Cipher {
  private llm: LlmClient | null;
  private rng: () => number;
  constructor(llm: LlmClient | null, rng: () => number = Math.random) { this.llm = llm; this.rng = rng; }

  async reply(input: CipherInput): Promise<CipherReply> {
    const history = sanitizeHistory(input.messages);
    const last = history[history.length - 1]!.text;
    if (isCrisis(last)) return CRISIS_REPLY;                      // deterministic, never sent to the model
    if (!this.llm) return offlineReply(last, this.rng);

    const tone: Tone = typeof input.tone === 'string' && input.tone in TONES ? (input.tone as Tone) : 'Blunt';
    const name = typeof input.name === 'string' ? cleanText(input.name).replace(/[^a-z0-9_ ]/gi, '').slice(0, 20) || 'player' : 'player';
    const loyalty = Math.max(0, Math.min(100, Math.round(Number(input.loyalty) || 70)));
    const hour = typeof input.hour === 'number' && input.hour >= 0 && input.hour < 24 ? Math.floor(input.hour) : null;
    const system = buildSystem({ name, tone, loyalty, hour, ctx: cleanCtx(input.ctx), band: input.band });
    try {
      const raw = await this.llm.json({ system, prompt: last, history: history.slice(0, -1), schema: CHAT_SCHEMA, timeoutMs: 15_000, temperature: 0.95 });
      return parseReply(raw);
    } catch (e) {
      log('warn', 'cipher llm failed', { err: e instanceof Error ? e.message.slice(0, 60) : 'unknown' });
      return { messages: ["signal's dropping on my end. try me again in a sec."], mood: 'worried', loyaltyDelta: 0 };
    }
  }
}
