alter table public.reels
add column if not exists transcript jsonb null;
