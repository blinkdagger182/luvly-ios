create table if not exists public.reel_social_profiles (
  id uuid primary key,
  handle text not null unique,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reel_bookmarks (
  profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  reel_id uuid not null references public.reels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, reel_id)
);

create table if not exists public.reel_public_shares (
  reel_id uuid primary key references public.reels(id) on delete cascade,
  profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  niche_tags text[] not null default '{}',
  share_count integer not null default 1,
  save_count integer not null default 0,
  view_count integer not null default 0,
  is_public boolean not null default true,
  shared_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reel_social_collections (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  name text not null,
  description text null,
  is_public boolean not null default false,
  share_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reel_social_collection_items (
  collection_id uuid not null references public.reel_social_collections(id) on delete cascade,
  reel_id uuid not null references public.reels(id) on delete cascade,
  order_index integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (collection_id, reel_id)
);

create table if not exists public.reel_friend_shares (
  id uuid primary key default gen_random_uuid(),
  sender_profile_id uuid not null references public.reel_social_profiles(id) on delete cascade,
  receiver_profile_id uuid null references public.reel_social_profiles(id) on delete set null,
  receiver_handle text null,
  reel_id uuid null references public.reels(id) on delete cascade,
  collection_id uuid null references public.reel_social_collections(id) on delete cascade,
  message text null,
  created_at timestamptz not null default now(),
  constraint reel_friend_shares_target_check check (reel_id is not null or collection_id is not null)
);

create index if not exists reel_bookmarks_reel_id_idx on public.reel_bookmarks (reel_id);
create index if not exists reel_public_shares_public_idx on public.reel_public_shares (is_public, shared_at desc);
create index if not exists reel_public_shares_niche_tags_idx on public.reel_public_shares using gin (niche_tags);
create index if not exists reel_social_collections_profile_idx on public.reel_social_collections (profile_id, created_at desc);
create index if not exists reel_social_collection_items_reel_idx on public.reel_social_collection_items (reel_id);
create index if not exists reel_friend_shares_receiver_handle_idx on public.reel_friend_shares (receiver_handle, created_at desc);
create index if not exists reel_friend_shares_receiver_profile_idx on public.reel_friend_shares (receiver_profile_id, created_at desc);

drop trigger if exists reel_social_profiles_set_updated_at on public.reel_social_profiles;
create trigger reel_social_profiles_set_updated_at
before update on public.reel_social_profiles
for each row execute function public.set_updated_at();

drop trigger if exists reel_public_shares_set_updated_at on public.reel_public_shares;
create trigger reel_public_shares_set_updated_at
before update on public.reel_public_shares
for each row execute function public.set_updated_at();

drop trigger if exists reel_social_collections_set_updated_at on public.reel_social_collections;
create trigger reel_social_collections_set_updated_at
before update on public.reel_social_collections
for each row execute function public.set_updated_at();
