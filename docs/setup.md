# Setup

## 0. Prerequisites
Node ≥ 22.18 (runs TypeScript natively), Flutter 3.47 or newer (the version in `pubspec.lock`; the glass uses squircle corners, which need a recent Flutter), an Android emulator or iPhone.

## 1. Supabase
1. Create a project. Copy the **Project URL**, **anon key**, **JWT secret** (legacy) or leave the secret blank if you use asymmetric signing keys, and the **pooled Postgres connection string** (Project Settings → Database).
2. SQL editor → run [`supabase/migrations/0001_init.sql`](../supabase/migrations/0001_init.sql).
3. Authentication → providers: enable Email. For quick tests, you may disable "Confirm email".
4. Make yourself a moderator after signing up once: `update public.profiles set role='moderator' where id='<your uuid>';`

## 2. Gemini
Create an API key in Google AI Studio. Put it in `server/.env` as `GEMINI_API_KEY`. `GEMINI_MODEL` defaults to `gemini-3.8-flash`; use any model that supports structured JSON output. Leave the key empty to run on approved fallback dares only.

## 3. LiveKit
Create a project at cloud.livekit.io (or self-host). Put `LIVEKIT_URL` (wss://…), `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` in `server/.env`. Nothing LiveKit-secret goes in the app.

## 3b. Clips and the Feed (optional)
The Feed works immediately in development with five labelled DEMO clips (`DEMO_CLIPS=1`): the videos and poster frames live in `server/public/demo` and are served at `/demo`. Replace them by putting new `dare-<name>.mp4` + `dare-<name>.jpg` pairs there and editing `server/src/seed.ts`. (On a physical phone the app reaches the server by its LAN address, and the feed hands out URLs built from that same address.) Real recording needs:
1. Run `supabase/migrations/0002_clips.sql`.
2. Storage → create a **private** bucket named `clips`.
3. Project Settings → Storage → S3 Connection → create access keys; put them in `server/.env` (`CLIPS_S3_*`) along with `SUPABASE_SERVICE_ROLE_KEY` (the server signs URLs with it; never put it in the app).
4. Your LiveKit project must have **Egress** enabled (LiveKit Cloud plans differ; check yours).
Recording stays disabled until all of this is set, and the game works without it.

## 3c. Upgrading from the 18+ version
Run `supabase/migrations/0007_age_16.sql` **once**, before starting the new server. It renames `adult_verified_at` to `age_verified_at`. Everyone who passed the old screen keeps their verification and is an adult account. Nothing else needs migrating: the age band is derived from `birth_date`.

## 3d. Following, chat and activity
Run `supabase/migrations/0008_follows_chat_activity.sql` **once**, after 0007. It adds the `follows`, `conversations`, `messages` and `notifications` tables. They are only reachable through the server. The Postgres code for these tables was written to match the in-memory version that the tests cover, but it has not been run against a live database in development: try follow, chat and activity once against a test database before you rely on it.

## 4. Server
```bash
cd server && npm install && cp .env.example .env && npm start
```
Production: `NODE_ENV=production`, `DEV_AUTH` off, `CORS_ORIGIN` set, `SUPABASE_URL` + `DATABASE_URL` required (the server refuses to start otherwise). Deploy the `Dockerfile` to Fly.io, Render, Railway or any container host; it needs WebSockets and one instance (see ADR 0003).

## 5. App
`mobile/env.json`:
```json
{ "API_URL": "https://your-server", "SUPABASE_URL": "https://xxx.supabase.co", "SUPABASE_ANON_KEY": "…", "DEV_AUTH": "false" }
```
Android emulator reaches your laptop at `http://10.0.2.2:3000`; a physical phone needs your LAN IP. Run `./setup.sh` once, then `flutter run --dart-define-from-file=env.json`.

## Troubleshooting
* **Photo picker does nothing on iOS** → run `dart run tool/patch_platforms.dart` again (it adds `NSPhotoLibraryUsageDescription`), then rebuild.
* **Gallery photo upload says the photo is too large** → the app shrinks photos to 512 px; the server accepts up to 500 KB. Try a different photo.
* **After pulling this update** → run `flutter pub get` (adds `image_picker`) and apply the new database migration `supabase/migrations/0004_social.sql` if you use Supabase.
* **No video** → check `LIVEKIT_*`; the game continues without it. Emulators often lack a camera: use a real phone for the Player.
* **`auth_failed` on socket** → token expired or the JWT secret / JWKS config does not match your project.
* **Cleartext blocked** → debug builds allow `http://`; release builds need https/wss.
