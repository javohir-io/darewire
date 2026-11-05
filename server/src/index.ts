import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { Director } from './director/director.ts';
import { GeminiClient } from './director/gemini.ts';
import { createApp } from './http/app.ts';
import { createVerifier } from './http/auth.ts';
import { createMedia } from './media/livekit.ts';
import { createEgress } from './media/egress.ts';
import { createStorage } from './media/storage.ts';
import { Recorder } from './realtime/recorder.ts';
import { seedDemoClips } from './seed.ts';
import { Cipher } from './cipher/service.ts';
import { attachGateway } from './realtime/gateway.ts';
import { SessionManager } from './realtime/manager.ts';
import { MemoryRepo } from './store/memory.ts';
import { PgRepo } from './store/pg.ts';
import type { Repo } from './store/types.ts';
import { loadConfig } from './util/config.ts';
import { log } from './util/log.ts';

const cfg = loadConfig();

const repo: Repo = cfg.databaseUrl ? new PgRepo(cfg.databaseUrl) : new MemoryRepo();
const llm = cfg.geminiKey ? new GeminiClient({ apiKey: cfg.geminiKey, model: cfg.geminiModel }) : null;
const director = new Director({ llm, review: cfg.aiReview, rng: Math.random, uid: randomUUID });
const media = createMedia(cfg.livekit);
const storage = createStorage({ supabaseUrl: cfg.supabaseUrl, serviceKey: cfg.supabaseServiceKey, bucket: cfg.clips.bucket });
const egress = createEgress(cfg.livekit, { accessKey: cfg.clips.s3AccessKey, secret: cfg.clips.s3Secret, endpoint: cfg.clips.s3Endpoint, region: cfg.clips.s3Region, bucket: cfg.clips.bucket });
const manager = new SessionManager({ repo, director, media, storage });
if (egress) manager.setRecorder(new Recorder({ repo, egress, storage, onReady: (s, u, c) => manager.offerClip(s, u, c) }));
const demoClips = cfg.clips.demo && !cfg.databaseUrl ? await seedDemoClips(repo) : 0;
const verify = createVerifier(cfg);

const restored = await manager.restore();
manager.startSweeper();

const app = createApp({ cfg, repo, manager, verify, storage, cipher: new Cipher(llm) });
const server = createServer(app);
attachGateway(server, { manager, verify, repo, relaxLimits: cfg.devAuth, allowedOrigins: cfg.corsOrigin === '*' ? [] : cfg.corsOrigin.split(',') });

server.listen(cfg.port, () => {
  log('info', 'DAREWIRE server up', {
    port: cfg.port, env: cfg.nodeEnv, storage: cfg.databaseUrl ? 'postgres' : 'memory',
    ai: llm ? `gemini:${cfg.geminiModel}` : 'fallback-only', aiReview: cfg.aiReview, video: media ? 'livekit' : 'disabled', devAuth: cfg.devAuth, restored, clipRecording: egress ? 'on' : 'off', demoClips,
  });
});

for (const sig of ['SIGTERM', 'SIGINT'] as const) {
  process.on(sig, async () => {
    log('info', 'shutting down', { sig });
    server.close();
    await manager.shutdown();
    process.exit(0);
  });
}
