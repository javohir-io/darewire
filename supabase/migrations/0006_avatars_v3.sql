-- DAREWIRE 0006: the built-in avatar set is now 12 images, a01 ... a12.
-- Every existing built-in avatar is replaced by one of the new ones, chosen from the user id so people are spread out.
-- Run this ONCE. Custom gallery photos (paths starting with /v1/avatars/) are not touched.
update public.profiles set avatar = 'a' || lpad(((abs(hashtext(id::text)) % 12) + 1)::text, 2, '0') where avatar ~ '^a[0-9]{2}$';
update public.clips c set author_avatar = p.avatar from public.profiles p where p.id = c.author_id and c.author_avatar ~ '^a[0-9]{2}$';
