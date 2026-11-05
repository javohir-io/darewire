-- DAREWIRE schema. Runs on Supabase Postgres (or any Postgres 14+ with an `auth.users` table).
-- The API server connects with a privileged role and enforces authorization itself; RLS is enabled everywhere
-- and left deny-by-default, so the public anon key can read almost nothing even if it leaks.

create extension if not exists pgcrypto;

do $$ begin
  create type user_role as enum ('user', 'moderator', 'admin');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  handle            text unique check (handle ~ '^[a-z0-9_]{3,20}$'),
  avatar            text not null default 'ghost',
  birth_date        date,                           -- self-declared; used only to enforce 18+
  adult_verified_at timestamptz,
  role              user_role not null default 'user',
  boundaries        jsonb not null default '{}'::jsonb,
  suspended_until   timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table if not exists public.sessions (
  id          uuid primary key,
  code        text not null unique,
  title       text not null,
  host_id     uuid references public.profiles (id) on delete set null,
  visibility  text not null default 'public' check (visibility in ('public', 'private')),
  status      text not null default 'active' check (status in ('active', 'ended')),
  phase       text not null,
  state       jsonb not null,                       -- authoritative engine snapshot (restart recovery)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  ended_at    timestamptz
);
create index if not exists sessions_active_idx on public.sessions (status, visibility, updated_at desc);

create table if not exists public.rounds (
  id            bigserial primary key,
  session_id    uuid not null references public.sessions (id) on delete cascade,
  round_no      int not null,
  player_id     uuid references public.profiles (id) on delete set null,
  challenge     jsonb,
  options       jsonb not null default '[]'::jsonb,
  tally         int[],
  outcome       text not null check (outcome in ('completed', 'failed', 'safety_stop', 'abandoned', 'moderated')),
  judged        boolean not null default false,
  player_points int not null default 0,
  result        jsonb not null,
  created_at    timestamptz not null default now(),
  unique (session_id, round_no)
);
create index if not exists rounds_player_idx on public.rounds (player_id, created_at desc);

-- One row per ballot. The primary key is the database-level guarantee that nobody votes twice in a round.
create table if not exists public.votes (
  round_id   bigint not null references public.rounds (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('challenge', 'twist', 'verdict')),
  choice     smallint not null,
  primary key (round_id, user_id, kind)
);

create table if not exists public.game_events (
  id          bigserial primary key,
  session_id  uuid not null references public.sessions (id) on delete cascade,
  rev         int not null,
  type        text not null,
  data        jsonb not null default '{}'::jsonb,
  at          timestamptz not null default now()
);
create index if not exists game_events_session_idx on public.game_events (session_id, rev);

create table if not exists public.ai_generations (
  id          bigserial primary key,
  session_id  uuid references public.sessions (id) on delete cascade,
  round_no    int,
  report      jsonb not null,                       -- counts and rejection reasons only: no user text
  created_at  timestamptz not null default now()
);

create table if not exists public.reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid references public.profiles (id) on delete set null,
  target_user_id  uuid references public.profiles (id) on delete set null,
  session_id      uuid references public.sessions (id) on delete set null,
  kind            text not null check (kind in ('unsafe_challenge', 'harassment', 'underage', 'sexual_content', 'spam', 'other')),
  note            text not null default '' check (char_length(note) <= 500),
  status          text not null default 'open' check (status in ('open', 'resolved')),
  resolution      text,
  resolved_by     uuid references public.profiles (id) on delete set null,
  resolved_at     timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists reports_status_idx on public.reports (status, created_at);

create table if not exists public.blocks (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.moderation_actions (
  id              bigserial primary key,
  moderator_id    uuid references public.profiles (id) on delete set null,
  action          text not null,
  target_user_id  uuid references public.profiles (id) on delete set null,
  session_id      uuid references public.sessions (id) on delete set null,
  report_id       uuid references public.reports (id) on delete set null,
  note            text not null default '',
  created_at      timestamptz not null default now()
);

-- A profile row appears automatically for every new Supabase Auth user.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---- Row Level Security: deny by default ---------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.sessions           enable row level security;
alter table public.rounds             enable row level security;
alter table public.votes              enable row level security;
alter table public.game_events        enable row level security;
alter table public.ai_generations     enable row level security;
alter table public.reports            enable row level security;
alter table public.blocks             enable row level security;
alter table public.moderation_actions enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (auth.uid() = id);

-- Public live sessions may be listed directly, but never their authoritative `state` column from the client:
-- the app always goes through the API. (Column privileges revoked below.)
drop policy if exists sessions_select_public on public.sessions;
create policy sessions_select_public on public.sessions for select to authenticated
  using (visibility = 'public' and status = 'active');
revoke select (state) on public.sessions from anon, authenticated;

drop policy if exists blocks_select_own on public.blocks;
create policy blocks_select_own on public.blocks for select to authenticated using (auth.uid() = blocker_id);
