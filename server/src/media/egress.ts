// LiveKit Egress: records ONLY the stage (the Player's camera and mic), never viewers or chat, straight into the clips bucket
// through Supabase Storage's S3-compatible endpoint. Requires egress on your LiveKit project (LiveKit Cloud or self-hosted).
// NOTE: written against livekit-server-sdk v2; not executed in the environment that produced this repo.
import { EgressClient, EncodedFileOutput, EncodedFileType, EgressStatus, S3Upload } from 'livekit-server-sdk';

export interface Egress {
  start(sessionId: string, filepath: string): Promise<string>;
  stop(egressId: string): Promise<void>;
  status(egressId: string): Promise<'active' | 'complete' | 'failed'>;
}

export interface S3Config { accessKey: string; secret: string; endpoint: string; region: string; bucket: string }

export function createEgress(lk: { url: string; apiKey: string; apiSecret: string }, s3: S3Config): Egress | null {
  if (!lk.url || !lk.apiKey || !lk.apiSecret || !s3.accessKey || !s3.secret || !s3.endpoint) return null;
  const client = new EgressClient(lk.url.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:'), lk.apiKey, lk.apiSecret);
  return {
    async start(sessionId, filepath) {
      const output = new EncodedFileOutput({
        fileType: EncodedFileType.MP4,
        filepath,
        output: { case: 's3', value: new S3Upload({ accessKey: s3.accessKey, secret: s3.secret, region: s3.region, endpoint: s3.endpoint, bucket: s3.bucket, forcePathStyle: true }) },
      });
      const info = await client.startRoomCompositeEgress(`dw_${sessionId}`, output, { layout: 'speaker' });
      return info.egressId;
    },
    async stop(id) { await client.stopEgress(id); },
    async status(id) {
      const list = await client.listEgress({ egressId: id });
      const s = list[0]?.status;
      if (s === EgressStatus.EGRESS_COMPLETE) return 'complete';
      if (s === EgressStatus.EGRESS_FAILED || s === EgressStatus.EGRESS_ABORTED || s === EgressStatus.EGRESS_LIMIT_REACHED) return 'failed';
      return 'active';
    },
  };
}
