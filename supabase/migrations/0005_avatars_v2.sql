-- DAREWIRE 0005: the built-in avatar set was reduced from 20 to 10 and renumbered a01 ... a10.
-- Run this ONCE. Old keys are mapped to the new numbers; avatars that were removed fall back to a01.
-- Custom gallery photos (paths starting with /v1/avatars/) are not touched.
update public.profiles set avatar = case avatar
  when 'a02' then 'a01' when 'a03' then 'a02' when 'a06' then 'a03' when 'a08' then 'a04' when 'a09' then 'a05'
  when 'a12' then 'a06' when 'a13' then 'a07' when 'a14' then 'a08' when 'a16' then 'a09' when 'a20' then 'a10'
  else 'a01' end
where avatar ~ '^a[0-9]{2}$';
update public.clips set author_avatar = case author_avatar
  when 'a02' then 'a01' when 'a03' then 'a02' when 'a06' then 'a03' when 'a08' then 'a04' when 'a09' then 'a05'
  when 'a12' then 'a06' when 'a13' then 'a07' when 'a14' then 'a08' when 'a16' then 'a09' when 'a20' then 'a10'
  else 'a01' end
where author_avatar ~ '^a[0-9]{2}$';
