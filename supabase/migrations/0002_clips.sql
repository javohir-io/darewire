-- DAREWIRE clips: opt-in recordings of finished dares, shown in the Feed.
-- Nothing is public until the Player explicitly publishes it; unpublished files expire after 24 h.

create table if not exists public.clips (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid references public.sessions (id) on delete set null,
  round_no       int,
  author_id      uuid not null references public.profiles (id) on delete cascade,
  author_handle  text not null,
  author_avatar  text not null default 'ghost',
  title          text not null,                 -- the dare's title
  caption        text not null default '' check (char_length(caption) <= 140),
  category       text not null,
  difficulty     int not null default 1,
  twist          text,
  duration_ms    int not null default 0,
  storage_path   text not null,                 -- object path in the private clips bucket
  status         text not null default 'awaiting' check (status in ('awaiting', 'published', 'hidden', 'removed')),
  likes          int not null default 0,
  views          int not null default 0,
  created_at     timestamptz not null default now(),
  published_at   timestamptz
);
create index if not exists clips_feed_idx on public.clips (status, published_at desc);
create index if not exists clips_author_idx on public.clips (author_id, created_at desc);

create table if not exists public.clip_likes (
  clip_id  uuid not null references public.clips (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  at       timestamptz not null default now(),
  primary key (clip_id, user_id)
);

create table if not exists public.clip_views (
  clip_id  uuid not null references public.clips (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  at       timestamptz not null default now(),
  primary key (clip_id, user_id)
);

alter table public.reports add column if not exists clip_id uuid references public.clips (id) on delete set null;

alter table public.clips      enable row level security;
alter table public.clip_likes enable row level security;
alter table public.clip_views enable row level security;
-- No policies: the app only reads clips through the API, which signs short-lived URLs for a private bucket.

-- Storage: create a PRIVATE bucket named "clips" (Dashboard > Storage > New bucket, "Public" OFF).
