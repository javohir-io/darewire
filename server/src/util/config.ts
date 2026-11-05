export interface Config {
  port: number;
  nodeEnv: string;
  devAuth: boolean;
  corsOrigin: string;
  databaseUrl: string;
  supabaseUrl: string;
  supabaseJwtSecret: string;
  supabaseServiceKey: string;
  geminiKey: string;
  geminiModel: string;
  aiReview: boolean;
  livekit: { url: string; apiKey: string; apiSecret: string };
  clips: { bucket: string; s3AccessKey: string; s3Secret: string; s3Endpoint: string; s3Region: string; demo: boolean };
}

const bool = (v: string | undefined, d: boolean) => (v === undefined || v === '' ? d : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase()));

export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
  const nodeEnv = env.NODE_ENV ?? 'development';
  const c: Config = {
    port: Number(env.PORT ?? 3000),
    nodeEnv,
    devAuth: bool(env.DEV_AUTH, nodeEnv !== 'production'),
    corsOrigin: env.CORS_ORIGIN ?? '*',
    databaseUrl: env.DATABASE_URL ?? '',
    supabaseUrl: (env.SUPABASE_URL ?? '').replace(/\/$/, ''),
    supabaseJwtSecret: env.SUPABASE_JWT_SECRET ?? '',
    supabaseServiceKey: env.SUPABASE_SERVICE_ROLE_KEY ?? '',
    geminiKey: env.GEMINI_API_KEY ?? '',
    geminiModel: env.GEMINI_MODEL ?? 'gemini-3.8-flash',
    aiReview: bool(env.AI_REVIEW, true),
    livekit: { url: env.LIVEKIT_URL ?? '', apiKey: env.LIVEKIT_API_KEY ?? '', apiSecret: env.LIVEKIT_API_SECRET ?? '' },
    clips: {
      bucket: env.CLIPS_BUCKET ?? 'clips', s3AccessKey: env.CLIPS_S3_ACCESS_KEY ?? '', s3Secret: env.CLIPS_S3_SECRET ?? '',
      s3Endpoint: env.CLIPS_S3_ENDPOINT ?? '', s3Region: env.CLIPS_S3_REGION ?? 'us-east-1',
      demo: bool(env.DEMO_CLIPS, nodeEnv !== 'production'),
    },
  };
  if (nodeEnv === 'production') {
    // Fail closed: production must never run with the development login or without real auth and storage.
    if (c.devAuth) throw new Error('DEV_AUTH must be off in production');
    if (!c.supabaseUrl) throw new Error('SUPABASE_URL is required in production');
    if (!c.databaseUrl) throw new Error('DATABASE_URL is required in production');
    if (c.corsOrigin === '*') throw new Error('Set CORS_ORIGIN in production');
    if (c.clips.demo) throw new Error('DEMO_CLIPS must be off in production');
  }
  return c;
}
