create table if not exists public.reel_ocr_entries (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  timestamp_seconds integer not null,
  text text not null,
  confidence real null,
  created_at timestamptz not null default now()
);

create index if not exists reel_ocr_entries_reel_id_time_idx
on public.reel_ocr_entries (reel_id, timestamp_seconds);
