// Private clip storage on Supabase Storage. The bucket is PRIVATE: the app only ever receives short-lived signed URLs.
// A path starting with "url:" is a demo clip served from a public sample URL (development only).
import { log } from '../util/log.ts';

export interface Storage {
  sign(paths: string[]): Promise<Record<string, string>>;
  remove(path: string): Promise<void>;
}

export function createStorage(cfg: { supabaseUrl: string; serviceKey: string; bucket: string }): Storage | null {
  if (!cfg.supabaseUrl || !cfg.serviceKey) return null;
  const base = `${cfg.supabaseUrl}/storage/v1`;
  const headers = { apikey: cfg.serviceKey, authorization: `Bearer ${cfg.serviceKey}`, 'content-type': 'application/json' };
  return {
    async sign(paths) {
      const out: Record<string, string> = {};
      const real = paths.filter((p) => !p.startsWith('url:'));
      for (const p of paths) if (p.startsWith('url:')) out[p] = p.slice(4);
      if (!real.length) return out;
      try {
        const r = await fetch(`${base}/object/sign/${cfg.bucket}`, { method: 'POST', headers, body: JSON.stringify({ expiresIn: 6 * 3600, paths: real }) });
        if (!r.ok) throw new Error(`sign_${r.status}`);
        const rows = (await r.json()) as { path?: string; signedURL?: string; signedUrl?: string }[];
        for (const row of rows) {
          const u = row.signedURL ?? row.signedUrl;
          if (row.path && u) out[row.path] = u.startsWith('http') ? u : `${base}${u.startsWith('/') ? '' : '/'}${u}`;
        }
      } catch (e) {
        log('warn', 'storage sign failed', { err: e instanceof Error ? e.message : 'unknown' });
      }
      return out;
    },
    async remove(path) {
      if (path.startsWith('url:')) return;
      try { await fetch(`${base}/object/${cfg.bucket}/${path}`, { method: 'DELETE', headers }); }
      catch (e) { log('warn', 'storage remove failed', { err: e instanceof Error ? e.message : 'unknown' }); }
    },
  };
}
