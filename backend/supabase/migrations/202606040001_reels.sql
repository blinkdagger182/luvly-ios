create extension if not exists "pgcrypto";

create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null,
  source text not null default 'instagram',
  source_url text not null,
  source_id text null,
  creator_username text null,
  creator_display_name text null,
  caption text null,
  thumbnail_url text null,
  duration_seconds integer null,
  video_url text null,
  title text null,
  category text null,
  summary text null,
  transcript jsonb null,
  status text not null default 'pending',
  error_message text null,
  raw_payload jsonb null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reel_segments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  start_seconds integer not null,
  end_seconds integer not null,
  title text not null,
  description text not null,
  raw_text text null,
  tags text[] not null default '{}',
  order_index integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists reels_source_url_idx on public.reels (source_url);
create index if not exists reels_created_at_idx on public.reels (created_at desc);
create index if not exists reel_segments_reel_id_order_idx on public.reel_segments (reel_id, order_index);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists reels_set_updated_at on public.reels;
create trigger reels_set_updated_at
before update on public.reels
for each row execute function public.set_updated_at();
