create table if not exists public.reel_profile_library (
  profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  reel_id uuid not null references public.reels(id) on delete cascade,
  added_at timestamptz not null default now(),
  last_opened_at timestamptz null,
  primary key (profile_id, reel_id)
);

create index if not exists reel_profile_library_profile_added_idx
on public.reel_profile_library (profile_id, added_at desc);

create index if not exists reel_profile_library_reel_idx
on public.reel_profile_library (reel_id);
