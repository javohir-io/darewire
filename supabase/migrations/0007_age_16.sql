-- DAREWIRE 0007: the minimum age moves from 18 to 16.
--
-- 1. The column "adult_verified_at" becomes "age_verified_at": a 16 or 17 year old is age-verified but not an adult.
--    Everyone who passed the old 18+ screen keeps their verification (their birth_date is 18 or over, so they are adults).
-- 2. Nothing else is stored for the age band. The server derives it from birth_date on every request
--    (16-17 = teen, 18 and over = adult), so a teen becomes an adult on their 18th birthday with no job to run.
--
-- Run this ONCE, before starting the new server version.
alter table public.profiles rename column adult_verified_at to age_verified_at;
comment on column public.profiles.birth_date is 'Self-declared date of birth. Used only to enforce the minimum age (16) and to derive the age band (teen 16-17, adult 18+). The first answer is final.';
comment on column public.profiles.age_verified_at is 'Set when the person gave a birth date that meets the minimum age. An under-age answer keeps birth_date but leaves this null, so it cannot be retried.';
