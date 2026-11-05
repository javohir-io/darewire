import { createRemoteJWKSet, jwtVerify } from 'jose';
import type { Config } from '../util/config.ts';

export interface AuthUser { id: string; handleHint?: string }
export type Verifier = (token: string) => Promise<AuthUser>;

/**
 * Verifies a Supabase Auth access token. Supports projects that use the legacy shared JWT secret (HS256)
 * and projects that use asymmetric signing keys (JWKS). In development, `dev:<id>:<handle>` is accepted when DEV_AUTH is on.
 */
export function createVerifier(cfg: Config): Verifier {
  const jwks = cfg.supabaseUrl ? createRemoteJWKSet(new URL(`${cfg.supabaseUrl}/auth/v1/.well-known/jwks.json`)) : null;
  const secret = cfg.supabaseJwtSecret ? new TextEncoder().encode(cfg.supabaseJwtSecret) : null;
  return async (token: string) => {
    if (cfg.devAuth && token.startsWith('dev:')) {
      const [, id, handle] = token.split(':');
      if (!id || !/^[a-z0-9-]{3,40}$/.test(id)) throw new Error('bad_dev_token');
      return { id, handleHint: handle };
    }
    if (token.length > 4096) throw new Error('token_too_long');
    const opts = { audience: 'authenticated', ...(cfg.supabaseUrl ? { issuer: `${cfg.supabaseUrl}/auth/v1` } : {}) };
    if (secret) {
      const { payload } = await jwtVerify(token, secret, { ...opts, algorithms: ['HS256'] });
      if (!payload.sub) throw new Error('no_sub');
      return { id: payload.sub };
    }
    if (jwks) {
      const { payload } = await jwtVerify(token, jwks, { ...opts, algorithms: ['ES256', 'RS256'] });
      if (!payload.sub) throw new Error('no_sub');
      return { id: payload.sub };
    }
    throw new Error('auth_not_configured');
  };
}
