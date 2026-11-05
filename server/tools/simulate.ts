// Concurrent-voting demo. Runs N SIMULATED viewers (not real users) against a running dev server and prints measured results.
//   terminal 1:  npm start               (DEV_AUTH=1, no database needed)
//   terminal 2:  npm run simulate -- 200  (default 100 viewers)
// Numbers it prints are from YOUR machine and YOUR run: report them with that context, never as general claims.
import { WebSocket } from 'ws';

const BASE = process.env.BASE ?? 'http://localhost:3000';
const WS = BASE.replace(/^http/, 'ws') + '/v1/ws';
const N = Number(process.argv[2] ?? 100);

const api = async (token: string, method: string, path: string, body?: unknown) => {
  const r = await fetch(BASE + path, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const j: any = r.status === 204 ? {} : await r.json();
  if (!r.ok && r.status !== 409) throw new Error(`${method} ${path} -> ${r.status} ${JSON.stringify(j)}`);
  return j;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const pct = (a: number[], p: number) => [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(a.length * p))] ?? 0;

class Sock {
  ws: WebSocket; state: any = null; pending = new Map<string, (d: any) => void>(); n = 0;
  constructor(public token: string, public sessionId: string, want: string) {
    this.ws = new WebSocket(WS);
    this.ws.on('open', () => this.ws.send(JSON.stringify({ type: 'auth', data: { token, sessionId, want } })));
    this.ws.on('message', (raw: any) => {
      const m = JSON.parse(String(raw));
      if (m.type === 'session:state') this.state = m.data;
      if (m.type === 'ack') { this.pending.get(m.id)?.(m.data); this.pending.delete(m.id); }
    });
  }
  cmd(type: string, data: unknown = {}): Promise<{ ok: boolean; ms: number }> {
    const id = String(++this.n), t = performance.now();
    return new Promise((res) => { this.pending.set(id, (d) => res({ ok: d.ok, ms: performance.now() - t })); this.ws.send(JSON.stringify({ type, id, data })); });
  }
  async until(pred: (s: any) => boolean, ms = 30000) { const t = Date.now(); while (Date.now() - t < ms) { if (this.state && pred(this.state)) return; await sleep(50); } throw new Error('timeout waiting for state'); }
}

const hostTok = 'dev:sim-host:sim_host';
await api(hostTok, 'POST', '/v1/me/age', { birthDate: '1990-01-01' });
const created = await api(hostTok, 'POST', '/v1/sessions', { title: `Simulation ${N}`, fast: true, twist: false });
const sessionId = created.id ?? created.sessionId;
const host = new Sock(hostTok, sessionId, 'player');

const viewers: Sock[] = [];
for (let i = 0; i < N; i++) {
  const tok = `dev:sim-viewer-${i}:sim_v${i}`;
  await api(tok, 'POST', '/v1/me/age', { birthDate: '1990-01-01' });
  viewers.push(new Sock(tok, sessionId, 'watcher'));
}
await Promise.all([host, ...viewers].map((s) => s.until((st) => !!st.you)));
console.log(`connected: 1 host + ${N} SIMULATED viewers`);

await host.cmd('session:start'); await host.cmd('player:ready');
await host.until((s) => s.phase === 'CHALLENGE_VOTE');

const t0 = performance.now();
const acks = await Promise.all(viewers.map(async (v, i) => { await sleep(Math.random() * 1500); return v.cmd('vote:cast', { option: i % 5 }); }));
const dupes = await Promise.all(viewers.slice(0, 20).map((v) => v.cmd('vote:cast', { option: 4 })));   // conflicting second votes
const lat = acks.map((a) => a.ms);
await host.until((s) => s.phase === 'PLAYER_REVIEW', 20000);
const tally: number[] = host.state.round.tally;

console.log(`votes accepted: ${acks.filter((a) => a.ok).length}/${N}`);
console.log(`conflicting second votes rejected: ${dupes.filter((a) => !a.ok).length}/${dupes.length}`);
console.log(`final tally: ${JSON.stringify(tally)}  (sum ${tally.reduce((a, b) => a + b, 0)}, winner option ${host.state.round.chosenIdx})`);
console.log(`vote ack latency ms: p50 ${pct(lat, 0.5).toFixed(1)}  p95 ${pct(lat, 0.95).toFixed(1)}  max ${Math.max(...lat).toFixed(1)}   (wall ${(performance.now() - t0).toFixed(0)} ms)`);
if (tally.reduce((a, b) => a + b, 0) !== N) { console.error('FAIL: tally does not equal the number of viewers'); process.exit(1); }
console.log('OK');
for (const s of [host, ...viewers]) s.ws.close();
process.exit(0);
