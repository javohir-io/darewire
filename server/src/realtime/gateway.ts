// WebSocket gateway. One socket = one user in one session.
//   1. client connects to /v1/ws and has 5 seconds to send {type:'auth', data:{token, sessionId, want}}
//   2. server verifies the Supabase JWT, checks adult/suspension status, joins the session and pushes a full authoritative snapshot
//   3. client sends commands {type, id, data}; server replies {type:'ack', id, data:{ok, error?}}
// Every state push carries `rev`, so clients can drop stale snapshots and recover after a reconnect by simply re-authing.
import type { IncomingMessage, Server } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer, type WebSocket } from 'ws';
import type { Verifier } from '../http/auth.ts';
import type { Repo } from '../store/types.ts';
import { RateLimiter } from '../util/ratelimit.ts';
import { log } from '../util/log.ts';
import type { Client, SessionManager } from './manager.ts';

export interface GatewayDeps { manager: SessionManager; verify: Verifier; repo: Repo; allowedOrigins?: string[]; relaxLimits?: boolean }

export function attachGateway(server: Server, deps: GatewayDeps): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 });
  const perIp = new RateLimiter(20, 0.5);        // new connections per IP

  server.on('upgrade', (req: IncomingMessage, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const ip = String(req.socket.remoteAddress ?? '');
    if (url.pathname !== '/v1/ws' || (!deps.relaxLimits && !perIp.take(ip))) { socket.destroy(); return; }
    const origin = req.headers.origin;
    if (origin && deps.allowedOrigins?.length && !deps.allowedOrigins.includes(origin)) { socket.destroy(); return; }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  wss.on('connection', (ws: WebSocket) => {
    let client: Client | null = null;
    let sessionId = '';
    let alive = true;
    const bucket = new RateLimiter(40, 20);       // 20 msgs/s sustained, bursts of 40
    const key = randomUUID();

    const send = (m: object) => {
      if (ws.readyState !== ws.OPEN) return;
      if (ws.bufferedAmount > 1_000_000) { ws.terminate(); return; }   // slow consumer: drop it rather than grow memory
      ws.send(JSON.stringify(m));
    };
    const fail = (code: string, close = true) => { send({ type: 'error', data: { code } }); if (close) ws.close(4000, code); };

    const authTimer = setTimeout(() => { if (!client) ws.close(4001, 'auth_timeout'); }, 5000);
    const hb = setInterval(() => { if (!alive) { ws.terminate(); return; } alive = false; ws.ping(); }, 20_000);
    ws.on('pong', () => { alive = true; });

    ws.on('message', async (raw) => {
      if (!bucket.take(key)) { ws.close(4008, 'rate_limited'); return; }
      let msg: { type?: unknown; id?: unknown; data?: any };
      try { msg = JSON.parse(String(raw)); } catch { return fail('bad_json'); }
      if (typeof msg.type !== 'string') return fail('bad_message');

      if (!client) {
        if (msg.type !== 'auth') return fail('auth_required');
        try {
          const { token, sessionId: sid, want } = msg.data ?? {};
          if (typeof token !== 'string' || typeof sid !== 'string') return fail('bad_auth');
          const user = await deps.verify(token);
          let profile = await deps.repo.ensureProfile(user.id);
          if (user.handleHint && !profile.handle) profile = await deps.repo.updateProfile(user.id, { handle: user.handleHint }).catch(() => profile);
          const suspended = profile.suspendedUntil && new Date(profile.suspendedUntil) > new Date();
          if (suspended) return fail('suspended');
          const isMod = profile.role !== 'user';
          if (!profile.ageVerifiedAt && !isMod) return fail('age_required');   // 16+ only (the age gate)
          if (!profile.handle) return fail('profile_incomplete');
          const c: Client = {
            id: key, userId: user.id, role: profile.role, observer: false, blocked: new Set(), send,
            close: (code, reason) => ws.close(code, reason),
          };
          const res = await deps.manager.connect(c, sid, profile, want === 'player' ? 'player' : want === 'observer' ? 'observer' : 'watcher');
          if (!res.ok) return fail(res.code);
          client = c; sessionId = sid; clearTimeout(authTimer);
          send({ type: 'ready', data: { userId: user.id, role: profile.role } });
        } catch (e) {
          log('warn', 'ws auth failed', { err: e instanceof Error ? e.message : 'unknown' });
          fail('auth_failed');
        }
        return;
      }

      const id = typeof msg.id === 'string' ? msg.id.slice(0, 64) : undefined;
      try {
        const res = await deps.manager.command(client, sessionId, msg.type, msg.data);
        if (id) send({ type: 'ack', id, data: res.ok ? { ok: true, ...(res.data ? { result: res.data } : {}) } : { ok: false, error: { code: res.code, message: res.message } } });
      } catch (e) {
        log('error', 'command failed', { type: msg.type, err: e instanceof Error ? e.message : 'unknown' });
        if (id) send({ type: 'ack', id, data: { ok: false, error: { code: 'internal', message: 'Something went wrong' } } });
      }
    });

    ws.on('close', () => {
      clearTimeout(authTimer); clearInterval(hb);
      if (client) deps.manager.disconnect(client, sessionId);
    });
    ws.on('error', () => ws.terminate());
  });

  return wss;
}
