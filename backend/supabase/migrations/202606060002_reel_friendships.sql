create table if not exists public.reel_friendships (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  receiver_profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reel_friendships_not_self_check check (requester_profile_id <> receiver_profile_id)
);

create unique index if not exists reel_friendships_pair_idx
on public.reel_friendships (
  least(requester_profile_id, receiver_profile_id),
  greatest(requester_profile_id, receiver_profile_id)
);

create index if not exists reel_friendships_requester_idx on public.reel_friendships (requester_profile_id, status);
create index if not exists reel_friendships_receiver_idx on public.reel_friendships (receiver_profile_id, status);

drop trigger if exists reel_friendships_set_updated_at on public.reel_friendships;
create trigger reel_friendships_set_updated_at
before update on public.reel_friendships
for each row execute function public.set_updated_at();
