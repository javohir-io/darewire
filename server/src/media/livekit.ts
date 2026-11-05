// LiveKit access control. The mobile app never holds LiveKit API credentials: it asks this server for a short-lived,
// room-scoped token, and the server only grants publish rights to the current Player of that session.
import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';
import { log } from '../util/log.ts';

export interface Media {
  url: string;
  roomName(sessionId: string): string;
  token(sessionId: string, identity: string, name: string, canPublish: boolean): Promise<string>;
  /** Remove a participant from the room (moderator stream cut). */
  cut(sessionId: string, identity: string): Promise<void>;
  /** Demote a participant to subscribe-only (stage hand-off). */
  revokePublish(sessionId: string, identity: string): Promise<void>;
  closeRoom(sessionId: string): Promise<void>;
}

export function createMedia(cfg: { url: string; apiKey: string; apiSecret: string }): Media | null {
  if (!cfg.url || !cfg.apiKey || !cfg.apiSecret) return null;
  const http = cfg.url.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
  const svc = new RoomServiceClient(http, cfg.apiKey, cfg.apiSecret);
  const roomName = (id: string) => `dw_${id}`;
  const safe = async (what: string, fn: () => Promise<unknown>) => { try { await fn(); } catch (e) { log('warn', `livekit ${what} failed`, { err: e instanceof Error ? e.message : 'unknown' }); } };
  return {
    url: cfg.url,
    roomName,
    async token(sessionId, identity, name, canPublish) {
      const at = new AccessToken(cfg.apiKey, cfg.apiSecret, { identity, name, ttl: '2h' });
      at.addGrant({ room: roomName(sessionId), roomJoin: true, canPublish, canSubscribe: true, canPublishData: false });
      return await at.toJwt();
    },
    cut: (s, id) => safe('removeParticipant', () => svc.removeParticipant(roomName(s), id)),
    revokePublish: (s, id) => safe('updateParticipant', () => svc.updateParticipant(roomName(s), id, undefined, { canSubscribe: true, canPublish: false, canPublishData: false } as never)),
    closeRoom: (s) => safe('deleteRoom', () => svc.deleteRoom(roomName(s))),
  };
}
