-- DAREWIRE 0008: following, direct messages and the activity feed. Run ONCE, after 0007.
-- Every access goes through the server (it enforces age bands, blocks and the teen chat rules), so no table is readable by clients.

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id, created_at desc);

-- One conversation per pair of people (user_a < user_b, so (a,b) and (b,a) are the same row).
create table public.conversations (
  id           uuid primary key default gen_random_uuid(),
  user_a       uuid not null references public.profiles(id) on delete cascade,
  user_b       uuid not null references public.profiles(id) on delete cascade,
  initiator_id uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'active' check (status in ('active', 'request', 'declined')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  last_read_a  timestamptz,
  last_read_b  timestamptz,
  unique (user_a, user_b),
  check (user_a < user_b)
);
create index conversations_a_idx on public.conversations (user_a, updated_at desc);
create index conversations_b_idx on public.conversations (user_b, updated_at desc);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  text            text not null check (char_length(text) between 1 and 500),
  created_at      timestamptz not null default now()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);

-- ref is '' (not null) when there is none, so the unique key below de-duplicates "X followed you" and "X liked Y".
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('follow', 'like', 'message_request', 'request_accepted')),
  actor_id   uuid not null references public.profiles(id) on delete cascade,
  ref        text not null default '',
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  unique (user_id, kind, actor_id, ref)
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.follows enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
