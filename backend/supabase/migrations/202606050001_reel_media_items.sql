alter table public.reels
add column if not exists media_items jsonb null;
