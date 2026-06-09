alter table public.reels
  add column if not exists reel_type text null,
  add column if not exists dominant_signal text null,
  add column if not exists signal_confidence real null;

create table if not exists public.reel_transcript_segments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  start_seconds real not null,
  end_seconds real not null,
  text text not null,
  confidence real null,
  is_music_like boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists reel_transcript_segments_reel_id_idx
  on public.reel_transcript_segments (reel_id, start_seconds);
