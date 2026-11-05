// Structured JSON logs. Never log tokens, API keys, chat text or full request bodies.
const SECRET = /(authorization|token|key|secret|password)/i;
export function log(level: 'info' | 'warn' | 'error', msg: string, ctx: Record<string, unknown> = {}): void {
  const safe: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(ctx)) safe[k] = SECRET.test(k) ? '[redacted]' : v;
  console[level === 'info' ? 'log' : level](JSON.stringify({ t: new Date().toISOString(), level, msg, ...safe }));
}
