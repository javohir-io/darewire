-- Public profile fields. Boundaries, birth date and role flags stay private; the API never returns them for other users.
alter table public.profiles add column if not exists bio    text not null default '' check (char_length(bio) <= 120);
alter table public.profiles add column if not exists accent text not null default 'ruby' check (accent in ('ruby', 'ember', 'gold', 'ice', 'violet', 'mint'));
