-- DAREWIRE 0004: gallery avatars, duels, points ledger, new profile accents, new built-in avatar keys.

-- Built-in avatars are now a01 ... a20. Anything else (old keys) falls back to a01.
alter table public.profiles alter column avatar set default 'a01';
update public.profiles set avatar = 'a01' where avatar !~ '^a[0-9]{2}$' and avatar !~ '^/v1/avatars/';
alter table public.clips alter column author_avatar set default 'a01';
update public.clips set author_avatar = 'a01' where author_avatar !~ '^a[0-9]{2}$' and author_avatar !~ '^/v1/avatars/';

-- Profile accents: new palette names.
alter table public.profiles drop constraint if exists profiles_accent_check;
update public.profiles set accent = case accent
  when 'ruby' then 'neon' when 'ember' then 'coral' when 'gold' then 'lime' when 'ice' then 'blue' when 'mint' then 'aqua' else accent end;
update public.profiles set accent = 'neon' where accent not in ('neon', 'pink', 'lime', 'blue', 'violet', 'aqua', 'coral');
alter table public.profiles alter column accent set default 'neon';
alter table public.profiles add constraint profiles_accent_check check (accent in ('neon', 'pink', 'lime', 'blue', 'violet', 'aqua', 'coral'));

-- Custom avatars uploaded from a phone's gallery. Resized on the device; the server validates type and size (max 500 KB).
create table if not exists public.avatars (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  mime       text not null check (mime in ('image/jpeg', 'image/png', 'image/webp')),
  data       bytea not null check (octet_length(data) <= 512000),
  updated_at timestamptz not null default now()
);
alter table public.avatars enable row level security;      -- deny by default: only the server (service role / direct connection) reads and writes

-- Duels: one player challenges another to a dare.
create table if not exists public.duels (
  id                uuid primary key,
  challenger_id     uuid not null references public.profiles(id) on delete cascade,
  challenger_handle text not null,
  challenger_avatar text not null,
  target_id         uuid not null references public.profiles(id) on delete cascade,
  target_handle     text not null,
  target_avatar     text not null,
  title             text not null,
  objective         text not null,
  category          text not null,
  difficulty        int  not null check (difficulty between 1 and 5),
  duration_seconds  int  not null,
  criteria          jsonb not null default '[]'::jsonb,
  origin            text not null check (origin in ('library', 'custom')),
  status            text not null check (status in ('pending', 'accepted', 'submitted', 'completed', 'rejected', 'declined', 'cancelled', 'expired')),
  note              text not null default '',
  proof_clip_id     uuid,
  reward            int  not null default 0,
  rewarded          int  not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  expires_at        timestamptz not null,
  resolved_at       timestamptz,
  check (challenger_id <> target_id)
);
create index if not exists duels_challenger_idx on public.duels (challenger_id, created_at desc);
create index if not exists duels_target_idx on public.duels (target_id, created_at desc);
alter table public.duels enable row level security;

-- Points ledger. `key` is unique, so every award (a duel, a daily quest) can be granted exactly once.
-- Points are not money. See docs/points-and-rewards.md before any cash-out feature is considered.
create table if not exists public.points_ledger (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  amount     int  not null,
  kind       text not null check (kind in ('duel_win', 'duel_bonus', 'quest', 'bonus')),
  ref        text not null default '',
  key        text not null unique,
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists points_ledger_user_idx on public.points_ledger (user_id, created_at desc);
alter table public.points_ledger enable row level security;
