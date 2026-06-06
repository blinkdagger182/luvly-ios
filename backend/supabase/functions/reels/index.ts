import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type Segment = {
  start_seconds: number;
  end_seconds: number;
  title: string;
  description: string;
  raw_text?: string;
  tags?: string[];
};

type NormalizedReel = Record<string, unknown> & {
  duration_seconds?: number | null;
  video_url?: string | null;
  media_items?: MediaItem[];
  transcript?: unknown;
  caption?: string | null;
  ocr_entries?: OCREntry[];
};

type MediaItem = {
  type: "image" | "video";
  url: string;
  thumbnail_url?: string | null;
  duration_seconds?: number | null;
  order_index: number;
};

type ReelSummary = {
  title: string;
  category: string;
  summary: string;
  segments: Segment[];
};

type TranscriptSegment = {
  start: number;
  end: number;
  text: string;
};

type OCREntry = {
  timestamp_seconds: number;
  text: string;
  confidence?: number | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
};

const supabaseUrl = requiredEnv("NEXT_PUBLIC_SUPABASE_URL");
const serviceRoleKey = requiredEnv("SERVICE_ROLE_KEY");
const apifyToken = requiredEnv("APIFY_TOKEN");
const openAIKey = requiredEnv("OPENAI_API_KEY");
const apifyActorId = Deno.env.get("APIFY_INSTAGRAM_REEL_ACTOR_ID") ?? "xMc5Ga1oCONPmWJIa";
const apifyTikTokActorId = Deno.env.get("APIFY_TIKTOK_ACTOR_ID") ?? "clockworks/tiktok-scraper";
const apifyInstagramPostActorId = Deno.env.get("APIFY_INSTAGRAM_POST_ACTOR_ID") ?? "apify/instagram-scraper";
const openAIModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

const supabase = createClient(supabaseUrl, serviceRoleKey);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    const socialIndex = parts.indexOf("social");
    if (socialIndex >= 0) {
      const action = parts[socialIndex + 1];
      return json(await handleSocial(request, url, action), request.method === "POST" ? 201 : 200);
    }

    const id = parts[parts.length - 1] !== "reels" ? parts[parts.length - 1] : undefined;

    if (request.method === "GET" && id) {
      return json(await getReel(id));
    }

    if (request.method === "GET") {
      const profileId = url.searchParams.get("profile_id");
      if (!profileId) throw new Error("Missing profile_id");
      return json(await listProfileLibrary(profileId, url));
    }

    if (request.method === "POST") {
      const body = await request.json();
      const sourceUrl = normalizeReelUrl(body.url);
      const profileId = uuidText(body.profile_id, "Missing profile_id");
      return json(await importReel(sourceUrl, profileId), 201);
    }

    if (request.method === "PATCH" && id) {
      const body = await request.json();
      return json(await updateReelOCR(id, body.entries));
    }

    if (request.method === "DELETE" && id) {
      const profileId = url.searchParams.get("profile_id");
      if (!profileId) throw new Error("Missing profile_id");
      return json(await removeReelFromLibrary(id, profileId));
    }

    return json({ error: "Method not allowed" }, 405);
  } catch (error) {
    console.error(error);
    return json({ error: errorMessage(error) }, 500);
  }
});

async function listProfileLibrary(profileId: string, url: URL) {
  await ensureSocialProfile(profileId);
  const limit = Math.min(Math.max(clampInt(Number(url.searchParams.get("limit") ?? 30), 30), 1), 50);
  const { data, error } = await supabase
    .from("reel_profile_library")
    .select("added_at, last_opened_at, reels(*, reel_segments(*), reel_ocr_entries(*))")
    .eq("profile_id", profileId)
    .order("added_at", { ascending: false })
    .limit(limit);

  if (error) throw error;
  return {
    reels: (data ?? [])
      .map((row: Record<string, unknown>) => {
        const reel = objectValue(row.reels);
        if (!reel) return null;
        return {
          ...reel,
          library: {
            added_at: row.added_at,
            last_opened_at: row.last_opened_at,
          },
        };
      })
      .filter((reel) => reel !== null),
  };
}

async function getReel(id: string) {
  const { data, error } = await supabase
    .from("reels")
    .select("*, reel_segments(*), reel_ocr_entries(*)")
    .eq("id", id)
    .single();

  if (error) throw error;
  return { reel: data };
}

async function removeReelFromLibrary(id: string, profileId: string) {
  const { error } = await supabase
    .from("reel_profile_library")
    .delete()
    .eq("profile_id", profileId)
    .eq("reel_id", id);

  if (error) throw error;
  return { ok: true };
}

async function handleSocial(request: Request, url: URL, action?: string) {
  if (request.method === "GET" && (!action || action === "summary")) {
    const profileId = url.searchParams.get("profile_id");
    if (!profileId) throw new Error("Missing profile_id");
    return await socialSummary(profileId);
  }

  if (request.method === "GET" && action === "profile") {
    const profileId = url.searchParams.get("profile_id");
    if (!profileId) throw new Error("Missing profile_id");
    return await getSocialProfile(profileId);
  }

  if (request.method === "GET" && action === "discover") {
    return await discoverSocialReels(
      url.searchParams.get("q") ?? "",
      url.searchParams.get("niche") ?? "",
      clampInt(Number(url.searchParams.get("limit") ?? 30), 30),
    );
  }

  if (request.method === "GET" && action === "friends") {
    const profileId = url.searchParams.get("profile_id");
    if (!profileId) throw new Error("Missing profile_id");
    return await friendState(profileId);
  }

  if (request.method === "GET" && action === "inbox") {
    const profileId = url.searchParams.get("profile_id");
    if (!profileId) throw new Error("Missing profile_id");
    return await shareInbox(profileId);
  }

  if (request.method !== "POST") {
    throw new Error("Method not allowed");
  }

  const body = await request.json();
  if (action === "profile") return await upsertSocialProfile(body);
  if (action === "bookmarks") return await setBookmark(body);
  if (action === "public-shares") return await setPublicShare(body);
  if (action === "collections") return await upsertSocialCollection(body);
  if (action === "friend-shares") return await shareWithFriend(body);
  if (action === "friends") return await requestFriend(body);
  if (action === "friend-response") return await respondToFriendRequest(body);

  throw new Error("Unknown social action");
}

async function socialSummary(profileId: string) {
  await ensureSocialProfile(profileId);
  const profile = await getSocialProfileRow(profileId);
  const handle = profile?.handle ?? `user-${profileId.slice(0, 8)}`;

  const [bookmarks, publicShares, collections, friendShares, friends] = await Promise.all([
    supabase.from("reel_bookmarks").select("reel_id, created_at").eq("profile_id", profileId),
    supabase.from("reel_public_shares").select("reel_id, niche_tags, share_count, save_count, view_count, shared_at").eq("profile_id", profileId).eq("is_public", true),
    supabase.from("reel_social_collections").select("*, reel_social_collection_items(reel_id, order_index)").eq("profile_id", profileId).order("created_at", { ascending: false }),
    supabase.from("reel_friend_shares").select("*, reel:reels(*, reel_segments(*), reel_ocr_entries(*)), collection:reel_social_collections(*)").or(`receiver_profile_id.eq.${profileId},receiver_handle.eq.${handle}`).order("created_at", { ascending: false }).limit(30),
    friendState(profileId),
  ]);

  if (bookmarks.error) throw bookmarks.error;
  if (publicShares.error) throw publicShares.error;
  if (collections.error) throw collections.error;
  if (friendShares.error) throw friendShares.error;

  return {
    bookmark_ids: (bookmarks.data ?? []).map((row) => row.reel_id),
    public_reel_ids: (publicShares.data ?? []).map((row) => row.reel_id),
    public_shares: publicShares.data ?? [],
    collections: collections.data ?? [],
    friend_shares: friendShares.data ?? [],
    friendships: friends.friendships,
    friends: friends.friends,
    incoming_friend_requests: friends.incoming_friend_requests,
    outgoing_friend_requests: friends.outgoing_friend_requests,
    niches: [],
    popular_reels: [],
  };
}

async function discoverSocialReels(query: string, niche: string, limit = 30) {
  const resultLimit = Math.min(Math.max(limit, 1), 50);
  let publicShareRequest = supabase
    .from("reel_public_shares")
    .select("reel_id, niche_tags, share_count, save_count, view_count, shared_at, reels(*, reel_segments(*), reel_ocr_entries(*))")
    .eq("is_public", true)
    .order("share_count", { ascending: false })
    .order("save_count", { ascending: false })
    .order("shared_at", { ascending: false })
    .limit(resultLimit);

  const normalizedNiche = normalizeNicheTag(niche);
  if (normalizedNiche) {
    publicShareRequest = publicShareRequest.contains("niche_tags", [normalizedNiche]);
  }

  const [publicShares, publicCollections] = await Promise.all([
    publicShareRequest,
    supabase
      .from("reel_social_collections")
      .select("id, name, created_at, reel_social_collection_items(reel_id, order_index, reels(*, reel_segments(*), reel_ocr_entries(*)))")
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(resultLimit),
  ]);

  if (publicShares.error) throw publicShares.error;
  if (publicCollections.error) throw publicCollections.error;

  const normalizedQuery = query.trim().toLowerCase();
  const publicShareRows: Record<string, unknown>[] = (publicShares.data ?? []).map((row: Record<string, unknown>) => ({
    ...row,
    source_rank: 0,
  }));
  const publicCollectionRows: Record<string, unknown>[] = (publicCollections.data ?? []).flatMap((collection: Record<string, unknown>) => {
    const collectionName = typeof collection.name === "string" ? collection.name : "Saved Reelplays";
    const collectionCreatedAt = typeof collection.created_at === "string" ? collection.created_at : null;
    const items = Array.isArray(collection.reel_social_collection_items)
      ? collection.reel_social_collection_items as Record<string, unknown>[]
      : [];

    return items.map((item) => ({
      reel_id: item.reel_id,
      niche_tags: [normalizeNicheTag(collectionName) ?? "saved"],
      share_count: 0,
      save_count: 0,
      view_count: 0,
      shared_at: collectionCreatedAt,
      reels: item.reels,
      source_rank: 1,
    }));
  });

  const rowsByReelId = new Map<string, Record<string, unknown>>();
  for (const row of [...publicShareRows, ...publicCollectionRows]) {
    const reel = objectValue(row.reels);
    const reelId = typeof reel?.id === "string" ? reel.id : (typeof row.reel_id === "string" ? row.reel_id : null);
    if (!reelId) continue;

    const existing = rowsByReelId.get(reelId);
    if (!existing || (numberValue(row.source_rank) ?? 1) < (numberValue(existing.source_rank) ?? 1)) {
      rowsByReelId.set(reelId, row);
    }
  }

  const rows = Array.from(rowsByReelId.values()).filter((row: Record<string, unknown>) => {
    if (!normalizedQuery) return true;
    const reel = objectValue(row.reels);
    const haystack = [
      reel?.title,
      reel?.summary,
      reel?.caption,
      reel?.category,
      reel?.creator_username,
      row.niche_tags,
    ]
      .flat()
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.toLowerCase())
      .join(" ");
    return haystack.includes(normalizedQuery);
  }).slice(0, resultLimit);

  const reels = rows
    .map((row: Record<string, unknown>) => {
      const reel = objectValue(row.reels);
      if (!reel?.id) return null;
      return {
        ...reel,
        social: {
        niche_tags: Array.isArray(row.niche_tags) ? row.niche_tags : [],
        share_count: numberValue(row.share_count) ?? 0,
        save_count: numberValue(row.save_count) ?? 0,
        view_count: numberValue(row.view_count) ?? 0,
        shared_at: row.shared_at,
        },
      };
    })
    .filter((reel) => reel !== null);

  const niches = Array.from(new Set(rows.flatMap((row: Record<string, unknown>) => (
    Array.isArray(row.niche_tags) ? row.niche_tags.filter((tag) => typeof tag === "string") : []
  )))).sort();

  return { reels, niches };
}

async function upsertSocialProfile(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const handle = normalizeHandle(textOrFallback(body.handle, `user-${profileId.slice(0, 8)}`));
  const displayName = textOrFallback(body.display_name, "Reelplay User");

  const { data, error } = await supabase
    .from("reel_social_profiles")
    .upsert({
      id: profileId,
      handle,
      display_name: displayName,
    }, { onConflict: "id" })
    .select()
    .single();

  if (error) throw error;
  return { profile: data };
}

async function getSocialProfile(profileId: string) {
  await ensureSocialProfile(profileId);
  return { profile: await getSocialProfileRow(profileId) };
}

async function getSocialProfileRow(profileId: string) {
  const { data, error } = await supabase
    .from("reel_social_profiles")
    .select("*")
    .eq("id", profileId)
    .single();
  if (error) throw error;
  return data;
}

async function ensureSocialProfile(profileId: string) {
  const { error } = await supabase
    .from("reel_social_profiles")
    .upsert({
      id: profileId,
      handle: `user-${profileId.slice(0, 8)}`,
      display_name: "Reelplay User",
    }, { onConflict: "id", ignoreDuplicates: true });

  if (error) throw error;
}

async function friendState(profileId: string) {
  await ensureSocialProfile(profileId);

  const { data: friendships, error } = await supabase
    .from("reel_friendships")
    .select("*")
    .or(`requester_profile_id.eq.${profileId},receiver_profile_id.eq.${profileId}`)
    .order("updated_at", { ascending: false })
    .limit(100);
  if (error) throw error;

  const friendRows = friendships ?? [];
  const profileIds = Array.from(new Set(friendRows.flatMap((row) => [
    row.requester_profile_id,
    row.receiver_profile_id,
  ]).filter((id) => id && id !== profileId)));

  const profiles = profileIds.length > 0
    ? await supabase.from("reel_social_profiles").select("*").in("id", profileIds)
    : { data: [], error: null };
  if (profiles.error) throw profiles.error;

  const profileById = new Map((profiles.data ?? []).map((profile) => [profile.id, profile]));
  const decorate = (row: Record<string, unknown>) => {
    const otherId = row.requester_profile_id === profileId ? row.receiver_profile_id : row.requester_profile_id;
    return {
      ...row,
      other_profile: typeof otherId === "string" ? profileById.get(otherId) ?? null : null,
    };
  };

  return {
    friendships: friendRows.map(decorate),
    friends: friendRows.filter((row) => row.status === "accepted").map(decorate),
    incoming_friend_requests: friendRows
      .filter((row) => row.status === "pending" && row.receiver_profile_id === profileId)
      .map(decorate),
    outgoing_friend_requests: friendRows
      .filter((row) => row.status === "pending" && row.requester_profile_id === profileId)
      .map(decorate),
  };
}

async function requestFriend(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const receiverHandle = normalizeHandle(textOrFallback(body.receiver_handle, ""));
  await ensureSocialProfile(profileId);

  const { data: receiver, error: receiverError } = await supabase
    .from("reel_social_profiles")
    .select("*")
    .eq("handle", receiverHandle)
    .maybeSingle();
  if (receiverError) throw receiverError;
  if (!receiver) throw new Error("No profile found with that handle");
  if (receiver.id === profileId) throw new Error("You cannot add yourself");

  const { data: existing, error: existingError } = await supabase
    .from("reel_friendships")
    .select("*")
    .or(`and(requester_profile_id.eq.${profileId},receiver_profile_id.eq.${receiver.id}),and(requester_profile_id.eq.${receiver.id},receiver_profile_id.eq.${profileId})`)
    .maybeSingle();
  if (existingError) throw existingError;

  if (!existing) {
    const { error } = await supabase
      .from("reel_friendships")
      .insert({
        requester_profile_id: profileId,
        receiver_profile_id: receiver.id,
        status: "pending",
      });
    if (error) throw error;
  }

  return await friendState(profileId);
}

async function respondToFriendRequest(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const friendshipId = uuidText(body.friendship_id, "Missing friendship_id");
  const response = textOrFallback(body.response, "accepted");
  const status = response === "accepted" ? "accepted" : "blocked";

  await ensureSocialProfile(profileId);

  const { error } = await supabase
    .from("reel_friendships")
    .update({ status })
    .eq("id", friendshipId)
    .eq("receiver_profile_id", profileId);
  if (error) throw error;

  return await friendState(profileId);
}

async function shareInbox(profileId: string) {
  await ensureSocialProfile(profileId);
  const profile = await getSocialProfileRow(profileId);
  const handle = profile?.handle ?? `user-${profileId.slice(0, 8)}`;

  const { data, error } = await supabase
    .from("reel_friend_shares")
    .select("*, reel:reels(*, reel_segments(*), reel_ocr_entries(*)), collection:reel_social_collections(*)")
    .or(`receiver_profile_id.eq.${profileId},receiver_handle.eq.${handle}`)
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw error;

  return { shares: data ?? [] };
}

async function setBookmark(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const reelId = uuidText(body.reel_id, "Missing reel_id");
  const isBookmarked = body.is_bookmarked !== false;

  await ensureSocialProfile(profileId);
  await addReelToProfileLibrary(profileId, reelId);

  if (isBookmarked) {
    const { error } = await supabase
      .from("reel_bookmarks")
      .upsert({ profile_id: profileId, reel_id: reelId }, { onConflict: "profile_id,reel_id" });
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from("reel_bookmarks")
      .delete()
      .eq("profile_id", profileId)
      .eq("reel_id", reelId);
    if (error) throw error;
  }

  await refreshPublicSaveCount(reelId);
  return await socialSummary(profileId);
}

async function setPublicShare(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const reelId = uuidText(body.reel_id, "Missing reel_id");
  const isPublic = body.is_public !== false;
  const nicheTags = normalizeNicheTags(body.niche_tags);

  await ensureSocialProfile(profileId);

  if (isPublic) {
    const { data: reel } = await supabase.from("reels").select("category").eq("id", reelId).maybeSingle();
    const fallbackTag = normalizeNicheTag(reel?.category);
    const tags = nicheTags.length > 0 ? nicheTags : (fallbackTag ? [fallbackTag] : ["general"]);

    const { error } = await supabase
      .from("reel_public_shares")
      .upsert({
        reel_id: reelId,
        profile_id: profileId,
        niche_tags: tags,
        is_public: true,
      }, { onConflict: "reel_id" });
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from("reel_public_shares")
      .update({ is_public: false })
      .eq("reel_id", reelId)
      .eq("profile_id", profileId);
    if (error) throw error;
  }

  return await socialSummary(profileId);
}

async function upsertSocialCollection(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const name = textOrFallback(body.name, "Saved reels");
  const description = textOrNull(body.description);
  const reelIds = Array.isArray(body.reel_ids) ? body.reel_ids.map((id) => uuidText(id, "Invalid reel_id")) : [];

  await ensureSocialProfile(profileId);
  for (const reelId of reelIds) {
    await addReelToProfileLibrary(profileId, reelId);
  }

  const { data: collection, error } = await supabase
    .from("reel_social_collections")
    .insert({
      profile_id: profileId,
      name,
      description,
      is_public: body.is_public === true,
    })
    .select()
    .single();

  if (error) throw error;

  if (reelIds.length > 0) {
    const { error: itemError } = await supabase
      .from("reel_social_collection_items")
      .insert(reelIds.map((reelId, index) => ({
        collection_id: collection.id,
        reel_id: reelId,
        order_index: index,
      })));
    if (itemError) throw itemError;
  }

  return await socialSummary(profileId);
}

async function shareWithFriend(body: Record<string, unknown>) {
  const profileId = profileIdFromBody(body);
  const reelId = body.reel_id ? uuidText(body.reel_id, "Invalid reel_id") : null;
  const collectionId = body.collection_id ? uuidText(body.collection_id, "Invalid collection_id") : null;
  if (!reelId && !collectionId) throw new Error("Missing reel_id or collection_id");

  const receiverHandle = body.receiver_handle ? normalizeHandle(textOrFallback(body.receiver_handle, "")) : null;
  const receiverProfileId = body.receiver_profile_id ? uuidText(body.receiver_profile_id, "Invalid receiver_profile_id") : null;

  await ensureSocialProfile(profileId);

  const { error } = await supabase.from("reel_friend_shares").insert({
    sender_profile_id: profileId,
    receiver_profile_id: receiverProfileId,
    receiver_handle: receiverHandle,
    reel_id: reelId,
    collection_id: collectionId,
    message: textOrNull(body.message),
  });
  if (error) throw error;

  if (reelId) {
    await incrementPublicShareCount(reelId);
  }

  return await socialSummary(profileId);
}

async function refreshPublicSaveCount(reelId: string) {
  const { count, error } = await supabase
    .from("reel_bookmarks")
    .select("*", { count: "exact", head: true })
    .eq("reel_id", reelId);
  if (error) throw error;

  await supabase
    .from("reel_public_shares")
    .update({ save_count: count ?? 0 })
    .eq("reel_id", reelId);
}

async function incrementPublicShareCount(reelId: string) {
  const { data, error } = await supabase
    .from("reel_public_shares")
    .select("share_count")
    .eq("reel_id", reelId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return;

  await supabase
    .from("reel_public_shares")
    .update({ share_count: (numberValue(data.share_count) ?? 0) + 1 })
    .eq("reel_id", reelId);
}

async function updateReelOCR(id: string, rawEntries: unknown) {
  const entries = normalizeOCREntries(rawEntries);

  await supabase.from("reel_ocr_entries").delete().eq("reel_id", id);

  if (entries.length === 0) {
    const { error } = await supabase
      .from("reels")
      .update({
        status: "ocr_failed",
        error_message: "On-device OCR found no readable on-screen text.",
      })
      .eq("id", id);

    if (error) throw error;
    return await getReel(id);
  }

  if (entries.length > 0) {
    const { error } = await supabase.from("reel_ocr_entries").insert(
      entries.map((entry) => ({
        reel_id: id,
        timestamp_seconds: entry.timestamp_seconds,
        text: entry.text,
        confidence: entry.confidence ?? null,
      })),
    );
    if (error) throw error;
  }

  const { data: reel, error: reelError } = await supabase
    .from("reels")
    .select("*")
    .eq("id", id)
    .single();

  if (reelError) throw reelError;

  const input = {
    ...reel,
    ocr_entries: entries,
  } as NormalizedReel;
  const summary = await summarizeReel(input);
  const segments = normalizeSegments(summary.segments, input);

  const { error: updateError } = await supabase
    .from("reels")
    .update({
      title: summary.title,
      category: summary.category,
      summary: summary.summary,
      status: "ready",
    })
    .eq("id", id);

  if (updateError) throw updateError;

  await supabase.from("reel_segments").delete().eq("reel_id", id);

  if (segments.length > 0) {
    const { error: segmentError } = await supabase.from("reel_segments").upsert(
      segments.map((segment, index) => ({
        reel_id: id,
        start_seconds: segment.start_seconds,
        end_seconds: segment.end_seconds,
        title: segment.title,
        description: segment.description,
        raw_text: segment.raw_text ?? null,
        tags: segment.tags,
        order_index: index,
      })),
      { onConflict: "reel_id,order_index" },
    );
    if (segmentError) throw segmentError;
  }

  return await getReel(id);
}

async function importReel(sourceUrl: string, profileId: string) {
  await ensureSocialProfile(profileId);

  const { data: existing } = await supabase
    .from("reels")
    .select("*, reel_segments(*)")
    .eq("source_url", sourceUrl)
    .maybeSingle();

  if (existing?.status === "ready") {
    await addReelToProfileLibrary(profileId, existing.id);
    return { reel: existing };
  }

  const { data: created, error: createError } = await supabase
    .from("reels")
    .upsert({
      source: detectSource(sourceUrl),
      source_url: sourceUrl,
      status: "processing",
      error_message: null,
    }, { onConflict: "source_url" })
    .select()
    .single();

  if (createError) throw createError;

  try {
    const source = detectSource(sourceUrl);
    const apifyItem = await runApify(sourceUrl, source);
    const normalized = await normalizeApifyItem(sourceUrl, apifyItem);
    const summary = await summarizeReel(normalized);

    const needsVisualOCR = hasVideoURL(normalized);
    const { data: reel, error: updateError } = await supabase
      .from("reels")
      .update({
        ...normalized,
        title: summary.title,
        category: summary.category,
        summary: summary.summary,
        raw_payload: apifyItem,
        status: needsVisualOCR ? "ready_basic" : "ready",
      })
      .eq("id", created.id)
      .select()
      .single();

    if (updateError) throw updateError;

    await supabase.from("reel_segments").delete().eq("reel_id", created.id);

    const segments = normalizeSegments(summary.segments, normalized);
    const segmentRows = segments.map((segment, index) => ({
      reel_id: created.id,
      start_seconds: clampInt(segment.start_seconds, 0),
      end_seconds: clampInt(segment.end_seconds, clampInt(segment.start_seconds, 0) + 1),
      title: segment.title,
      description: segment.description,
      raw_text: segment.raw_text ?? null,
      tags: segment.tags,
      order_index: index,
    }));

    if (segmentRows.length > 0) {
      const { error: segmentError } = await supabase
        .from("reel_segments")
        .upsert(segmentRows, { onConflict: "reel_id,order_index" });
      if (segmentError) throw segmentError;
    }

    await addReelToProfileLibrary(profileId, reel.id);
    return await getReel(reel.id);
  } catch (error) {
    await supabase
      .from("reels")
      .update({
        status: "failed",
        error_message: errorMessage(error),
      })
      .eq("id", created.id);
    throw error;
  }
}

async function addReelToProfileLibrary(profileId: string, reelId: string) {
  const { error } = await supabase
    .from("reel_profile_library")
    .upsert({
      profile_id: profileId,
      reel_id: reelId,
      added_at: new Date().toISOString(),
    }, { onConflict: "profile_id,reel_id" });
  if (error) throw error;
}

async function runApify(sourceUrl: string, source = detectSource(sourceUrl)) {
  const actor = actorForSource(sourceUrl, source);
  const input = apifyInputForSource(sourceUrl, source);

  const runResponse = await fetch(`https://api.apify.com/v2/acts/${encodeURIComponent(actor)}/runs?token=${apifyToken}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });

  if (!runResponse.ok) {
    throw new Error(`Apify run failed: ${await runResponse.text()}`);
  }

  const run = await runResponse.json();
  const runId = run.data.id;

  let defaultDatasetId: string | undefined;
  for (let attempt = 0; attempt < 90; attempt += 1) {
    await delay(2000);
    const statusResponse = await fetch(`https://api.apify.com/v2/actor-runs/${runId}?token=${apifyToken}`);
    const status = await statusResponse.json();
    const runData = status.data;

    if (runData.status === "SUCCEEDED") {
      defaultDatasetId = runData.defaultDatasetId;
      break;
    }

    if (["FAILED", "ABORTED", "TIMED-OUT"].includes(runData.status)) {
      throw new Error(`Apify run ended with status ${runData.status}`);
    }
  }

  if (!defaultDatasetId) {
    throw new Error("Apify run did not finish in time");
  }

  const itemsResponse = await fetch(`https://api.apify.com/v2/datasets/${defaultDatasetId}/items?clean=true&limit=1&token=${apifyToken}`);
  if (!itemsResponse.ok) {
    throw new Error(`Apify dataset fetch failed: ${await itemsResponse.text()}`);
  }

  const items = await itemsResponse.json();
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error("Apify returned no reel items");
  }

  return items[0];
}

function actorForSource(sourceUrl: string, source: string) {
  if (source === "tiktok") return apifyTikTokActorId;
  if (isInstagramPostURL(sourceUrl)) return apifyInstagramPostActorId;
  return apifyActorId;
}

function apifyInputForSource(sourceUrl: string, source: string) {
  if (source === "tiktok") {
    return {
      postURLs: [sourceUrl],
      startUrls: [sourceUrl],
      resultsPerPage: 1,
      maxItems: 1,
      shouldDownloadVideos: false,
      shouldDownloadCovers: false,
      shouldDownloadSlideshowImages: false,
      proxyConfiguration: { useApifyProxy: true },
    };
  }

  return {
    username: [sourceUrl],
    directUrls: [sourceUrl],
    startUrls: [sourceUrl],
    resultsLimit: 1,
    resultsType: "posts",
    skipPinnedPosts: false,
    includeSharesCount: false,
    includeTranscript: false,
    includeDownloadedVideo: false,
  };
}

async function normalizeApifyItem(sourceUrl: string, item: Record<string, unknown>): Promise<NormalizedReel> {
  const source = detectSource(sourceUrl);
  let transcript = extractTranscript(item);
  const mediaItems = extractMediaItems(item);
  const videoUrl = extractVideoUrl(item, mediaItems);
  const shouldTranscribeAudio = typeof videoUrl === "string" && videoUrl.length > 0;
  if (shouldTranscribeAudio && !hasTimestampedTranscript(transcript)) {
    transcript = await transcribeAudioWithTimestamps(item) ?? transcript;
  }
  const owner = objectValue(item.owner);
  const author = objectValue(item.authorMeta) ?? objectValue(item.author);
  const caption = stringValue(item.caption) ?? stringValue(item.text) ?? stringValue(item.description);
  const duration = numberValue(item.videoDuration) ??
    numberValue(item.duration) ??
    numberValue(item.durationSeconds) ??
    numberValue(objectValue(item.videoMeta)?.duration) ??
    slideshowDuration(mediaItems);
  const ocrEntries = mediaItems.length > 0 && !videoUrl ? mediaItemsToOCREntries(mediaItems, caption) : undefined;

  return {
    source,
    source_url: sourceUrl,
    source_id: stringValue(item.id) ?? stringValue(item.shortCode) ?? stringValue(item.shortcode) ?? stringValue(item.awemeId),
    creator_username: stringValue(item.ownerUsername) ?? stringValue(item.username) ?? stringValue(owner?.username) ?? stringValue(author?.name) ?? stringValue(author?.uniqueId),
    creator_display_name: stringValue(item.ownerFullName) ?? stringValue(item.fullName) ?? stringValue(owner?.fullName) ?? stringValue(author?.nickName) ?? stringValue(author?.nickname),
    caption,
    thumbnail_url: extractThumbnailUrl(item, mediaItems),
    duration_seconds: duration,
    video_url: videoUrl,
    media_items: mediaItems,
    ocr_entries: ocrEntries,
    transcript,
  };
}

async function summarizeReel(input: Record<string, unknown>): Promise<ReelSummary> {
  const prompt = {
    role: "user",
    content: [
      "Convert this short-form video into useful timestamped note segments.",
      "Return strict JSON with title, category, summary, and segments.",
      "Each segment must have start_seconds, end_seconds, title, description, raw_text, and tags.",
      "Use snake_case keys exactly. Segments must use integer seconds and should cover the reel in order.",
      "When timestamped transcript items are provided, choose segment boundaries from those timestamps.",
      "When ocr_entries are provided, use their timestamp_seconds and text as visual on-screen context.",
      "When media_items are provided without video_url, treat the content as an image slideshow.",
      "For image slideshows, use the synthetic timestamps and any per-slide visual text to create replayable slide segments.",
      "If transcript is sparse but OCR is useful, prefer OCR-derived boundaries and titles.",
      "If on-screen text changes over time, each meaningful text change should usually become its own segment.",
      "For workout/list reels, split visible exercise or step lines into separate replayable segments when possible.",
      "Return 4 to 8 high-signal segments. Do not return null values.",
      JSON.stringify(input),
    ].join("\n\n"),
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      messages: [
        {
          role: "system",
          content: "You create concise timestamped learning notes from reels. Respond only with valid JSON.",
        },
        prompt,
      ],
      response_format: { type: "json_object" },
      temperature: 0.2,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI summary failed: ${await response.text()}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  const parsed = JSON.parse(content) as ReelSummary;

  return {
    title: parsed.title || "Saved reel",
    category: parsed.category || "general",
    summary: parsed.summary || "",
    segments: Array.isArray(parsed.segments) ? parsed.segments : [],
  };
}

function normalizeSegments(rawSegments: unknown[], input: NormalizedReel): Segment[] {
  const duration = clampInt(input.duration_seconds, 60);
  const segments = rawSegments
    .map((rawSegment, index) => normalizeSegment(rawSegment, index, duration))
    .filter((segment) => segment.description.length > 0 || segment.raw_text);

  const hasUsefulDescriptions = segments.some((segment) => segment.description.length > 0);
  if (segments.length >= 2 && hasUsefulDescriptions) {
    return segments;
  }

  return fallbackSegments(input);
}

function normalizeSegment(rawSegment: unknown, index: number, duration: number): Segment {
  const segment = objectValue(rawSegment) ?? {};
  const start = clampInt(
    segment.start_seconds ?? segment.startSeconds ?? segment.start ?? segment.start_time ?? segment.startTime,
    Math.floor((duration / 6) * index),
  );
  const end = clampInt(
    segment.end_seconds ?? segment.endSeconds ?? segment.end ?? segment.end_time ?? segment.endTime,
    Math.min(duration, start + Math.max(1, Math.floor(duration / 6))),
  );
  const rawText = textOrNull(segment.raw_text ?? segment.rawText ?? segment.text);
  const description = textOrFallback(segment.description ?? segment.summary ?? segment.text, rawText ?? "");

  return {
    start_seconds: start,
    end_seconds: Math.max(start + 1, end),
    title: textOrFallback(segment.title ?? segment.name, rawText ? titleFromText(rawText) : `Segment ${index + 1}`),
    description,
    raw_text: rawText ?? undefined,
    tags: Array.isArray(segment.tags) ? segment.tags.filter((tag) => typeof tag === "string") : [],
  };
}

function fallbackSegments(input: NormalizedReel): Segment[] {
  const duration = clampInt(input.duration_seconds, 60);
  if (Array.isArray(input.media_items) && input.media_items.length > 0 && !hasVideoURL(input)) {
    return fallbackMediaItemSegments(input.media_items, input.caption ?? undefined);
  }

  if (hasOCREntries(input.ocr_entries)) {
    return fallbackOCRSegments(input.ocr_entries, duration);
  }

  if (hasTimestampedTranscript(input.transcript)) {
    return fallbackTimestampedSegments(input.transcript as TranscriptSegment[]);
  }

  const transcript = transcriptText(input.transcript) || input.caption || "Saved reel.";
  const sentences = transcript
    .split(/(?<=[.!?])\s+|\n+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  const chunks = chunkText(sentences.length > 0 ? sentences : [transcript], 6);

  return chunks.map((text, index) => {
    const start = Math.floor((duration / chunks.length) * index);
    const end = index === chunks.length - 1 ? duration : Math.floor((duration / chunks.length) * (index + 1));
    return {
      start_seconds: start,
      end_seconds: Math.max(start + 1, end),
      title: titleFromText(text),
      description: text,
      raw_text: text,
      tags: [],
    };
  });
}

function fallbackMediaItemSegments(mediaItems: MediaItem[], caption?: string): Segment[] {
  const items = mediaItems
    .filter((item) => item.url.length > 0)
    .sort((a, b) => a.order_index - b.order_index);
  const slideDuration = 3;
  const captionLines = splitCaptionLines(caption);

  return items.map((item, index) => {
    const text = captionLines[index] ?? captionLines[0] ?? `Slide ${index + 1}`;
    const start = index * slideDuration;
    return {
      start_seconds: start,
      end_seconds: start + slideDuration,
      title: titleFromText(text),
      description: text,
      raw_text: text,
      tags: [item.type, "slideshow"],
    };
  });
}

function fallbackOCRSegments(entries: OCREntry[], duration: number): Segment[] {
  const usefulEntries = entries
    .filter((entry) => entry.text.trim().length > 0)
    .sort((a, b) => a.timestamp_seconds - b.timestamp_seconds);
  const visualEvents = expandOCRVisualEvents(usefulEntries, duration);

  return visualEvents.map((entry, index) => {
    const text = entry.text.trim();
    const start = clampInt(entry.timestamp_seconds, 0);
    const nextStart = visualEvents[index + 1]?.timestamp_seconds;
    return {
      start_seconds: start,
      end_seconds: Math.max(start + 1, Math.min(duration, nextStart ?? start + Math.max(2, Math.ceil(duration / Math.max(visualEvents.length, 1))))),
      title: titleFromText(text),
      description: text,
      raw_text: text,
      tags: ["ocr"],
    };
  });
}

function expandOCRVisualEvents(entries: OCREntry[], duration: number): OCREntry[] {
  const collapsed: OCREntry[] = [];
  let previousKey = "";

  for (const entry of entries) {
    const key = normalizeOCRText(entry.text);
    if (!key || key === previousKey) continue;
    previousKey = key;
    collapsed.push({ ...entry, text: dedupeTexts(ocrTextLines(entry.text)).join("\n") || entry.text });
  }

  const expanded: OCREntry[] = [];
  for (const entry of collapsed) {
    const lines = ocrTextLines(entry.text);
    const shouldSplitLines = collapsed.length <= 2 && lines.length >= 2;

    if (!shouldSplitLines) {
      expanded.push({ ...entry, text: lines.join(" ") || entry.text });
      continue;
    }

    lines.slice(0, 8).forEach((line, index) => {
      expanded.push({
        ...entry,
        timestamp_seconds: Math.min(duration - 1, entry.timestamp_seconds + index),
        text: line,
      });
    });
  }

  return expanded.length > 0 ? expanded : entries;
}

function fallbackTimestampedSegments(transcript: TranscriptSegment[]): Segment[] {
  const usefulTranscript = transcript
    .filter((segment) => segment.text.trim().length > 0)
    .sort((a, b) => a.start - b.start);
  const groups = chunkItems(usefulTranscript, Math.min(7, Math.max(1, usefulTranscript.length)));

  return groups.map((group) => {
    const text = group.map((segment) => segment.text.trim()).join(" ");
    return {
      start_seconds: Math.floor(group[0].start),
      end_seconds: Math.ceil(group[group.length - 1].end),
      title: titleFromText(text),
      description: text,
      raw_text: text,
      tags: [],
    };
  });
}

function extractVideoUrl(item: Record<string, unknown>, mediaItems: MediaItem[]) {
  const videoMeta = objectValue(item.videoMeta);
  const urls = [
    item.videoUrl,
    item.video_url,
    item.downloadedVideoUrl,
    item.webVideoUrl,
    item.video,
    videoMeta?.downloadAddr,
    videoMeta?.playAddr,
    videoMeta?.url,
    ...mediaItems.filter((mediaItem) => mediaItem.type === "video").map((mediaItem) => mediaItem.url),
  ];

  return urls.map(stringValue).find((url) => !!url) ?? null;
}

function extractThumbnailUrl(item: Record<string, unknown>, mediaItems: MediaItem[]) {
  const videoMeta = objectValue(item.videoMeta);
  const urls = [
    item.displayUrl,
    item.thumbnailUrl,
    item.thumbnail,
    item.coverUrl,
    item.coversDefault,
    item.coversOrigin,
    item.coversDynamic,
    videoMeta?.coverUrl,
    videoMeta?.cover,
    mediaItems[0]?.thumbnail_url,
    mediaItems[0]?.url,
  ];

  return urls.map(stringValue).find((url) => !!url) ?? null;
}

function extractMediaItems(item: Record<string, unknown>): MediaItem[] {
  const mediaItems: MediaItem[] = [];
  appendMediaItems(mediaItems, item.media_items);
  appendMediaItems(mediaItems, item.mediaItems);
  appendMediaItems(mediaItems, item.images);
  appendMediaItems(mediaItems, item.imageUrls);
  appendMediaItems(mediaItems, item.image_urls);
  appendMediaItems(mediaItems, item.slideshowImageLinks);
  appendMediaItems(mediaItems, item.slideshowImages);
  appendMediaItems(mediaItems, item.carouselMedia);
  appendMediaItems(mediaItems, item.carousel_media);
  appendMediaItems(mediaItems, item.childPosts);
  appendMediaItems(mediaItems, item.children);

  const imagePostUrl = stringValue(item.displayUrl) ?? stringValue(item.imageUrl) ?? stringValue(item.image_url);
  const hasVideo = !!(stringValue(item.videoUrl) ?? stringValue(item.video_url) ?? stringValue(item.webVideoUrl));
  if (imagePostUrl && !hasVideo) {
    mediaItems.push({
      type: "image",
      url: imagePostUrl,
      thumbnail_url: imagePostUrl,
      order_index: mediaItems.length,
    });
  }

  return dedupeMediaItems(mediaItems);
}

function appendMediaItems(output: MediaItem[], value: unknown) {
  if (!Array.isArray(value)) return;

  for (const rawItem of value) {
    const index = output.length;
    if (typeof rawItem === "string" && rawItem.length > 0) {
      output.push({ type: inferMediaType(rawItem), url: rawItem, thumbnail_url: rawItem, order_index: index });
      continue;
    }

    const item = objectValue(rawItem);
    if (!item) continue;
    const videoMeta = objectValue(item.videoMeta);
    const url = stringValue(item.url) ??
      stringValue(item.src) ??
      stringValue(item.displayUrl) ??
      stringValue(item.imageUrl) ??
      stringValue(item.image_url) ??
      stringValue(item.videoUrl) ??
      stringValue(item.video_url) ??
      stringValue(videoMeta?.downloadAddr) ??
      stringValue(videoMeta?.playAddr);
    if (!url) continue;

    const thumbnail = stringValue(item.thumbnailUrl) ??
      stringValue(item.thumbnail) ??
      stringValue(item.displayUrl) ??
      stringValue(item.coverUrl) ??
      stringValue(videoMeta?.coverUrl) ??
      (inferMediaType(url) === "image" ? url : null);
    const explicitType = stringValue(item.type) ?? stringValue(item.mediaType) ?? stringValue(item.media_type);
    output.push({
      type: explicitType?.toLowerCase().includes("video") ? "video" : inferMediaType(url),
      url,
      thumbnail_url: thumbnail,
      duration_seconds: numberValue(item.duration) ?? numberValue(item.durationSeconds) ?? numberValue(videoMeta?.duration),
      order_index: numberValue(item.orderIndex) ?? numberValue(item.order_index) ?? index,
    });
  }
}

function dedupeMediaItems(items: MediaItem[]) {
  const seen = new Set<string>();
  return items
    .filter((item) => {
      if (seen.has(item.url)) return false;
      seen.add(item.url);
      return true;
    })
    .map((item, index) => ({ ...item, order_index: index }));
}

function inferMediaType(url: string): "image" | "video" {
  return /\.(mp4|mov|m3u8|webm)(?:[?#].*)?$/i.test(url) ? "video" : "image";
}

function slideshowDuration(mediaItems: MediaItem[]) {
  if (mediaItems.length === 0) return null;
  return mediaItems.reduce((total, item) => total + (item.duration_seconds ?? 3), 0);
}

function mediaItemsToOCREntries(mediaItems: MediaItem[], caption?: string | null): OCREntry[] {
  const captionLines = splitCaptionLines(caption ?? undefined);
  return mediaItems.map((item, index) => ({
    timestamp_seconds: index * 3,
    text: captionLines[index] ?? captionLines[0] ?? `Slide ${index + 1}`,
    confidence: null,
  }));
}

function splitCaptionLines(caption?: string): string[] {
  if (!caption) return [];
  return caption
    .split(/\n+|(?:\s*[•·]\s*)|(?:\s+-\s+)/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter((line) => line.length > 0)
    .slice(0, 12);
}

function hasVideoURL(input: NormalizedReel) {
  return typeof input.video_url === "string" && input.video_url.length > 0;
}

function transcriptText(transcript: unknown): string {
  if (typeof transcript === "string") return transcript;
  if (!Array.isArray(transcript)) return "";

  return transcript
    .map((entry) => objectValue(entry)?.text)
    .filter((text): text is string => typeof text === "string")
    .join(" ");
}

function chunkText(parts: string[], maxChunks: number): string[] {
  const chunkCount = Math.min(maxChunks, Math.max(1, parts.length));
  const chunks: string[] = [];
  for (let index = 0; index < chunkCount; index += 1) {
    const start = Math.floor((parts.length / chunkCount) * index);
    const end = Math.floor((parts.length / chunkCount) * (index + 1));
    chunks.push(parts.slice(start, Math.max(start + 1, end)).join(" "));
  }
  return chunks.filter(Boolean);
}

function chunkItems<T>(items: T[], chunkCount: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < chunkCount; index += 1) {
    const start = Math.floor((items.length / chunkCount) * index);
    const end = Math.floor((items.length / chunkCount) * (index + 1));
    chunks.push(items.slice(start, Math.max(start + 1, end)));
  }
  return chunks.filter((chunk) => chunk.length > 0);
}

function titleFromText(text: string) {
  const words = text.replace(/\s+/g, " ").trim().split(" ").slice(0, 7).join(" ");
  return words.length > 0 ? words : "Segment";
}

function hasTimestampedTranscript(transcript: unknown): transcript is TranscriptSegment[] {
  return Array.isArray(transcript) && transcript.some((entry) => {
    const segment = objectValue(entry);
    return typeof segment?.start === "number" &&
      typeof segment?.end === "number" &&
      typeof segment?.text === "string";
  });
}

function hasOCREntries(entries: unknown): entries is OCREntry[] {
  return Array.isArray(entries) && entries.some((entry) => {
    const ocrEntry = objectValue(entry);
    return typeof ocrEntry?.timestamp_seconds === "number" &&
      typeof ocrEntry?.text === "string" &&
      ocrEntry.text.trim().length > 0;
  });
}

function normalizeOCREntries(rawEntries: unknown): OCREntry[] {
  if (!Array.isArray(rawEntries)) return [];

  return rawEntries
    .map((rawEntry) => {
      const entry = objectValue(rawEntry);
      return {
        timestamp_seconds: clampInt(
          entry?.timestamp_seconds ?? entry?.timestampSeconds ?? entry?.time ?? entry?.timestamp,
          0,
        ),
        text: textOrFallback(entry?.text, ""),
        confidence: numberValue(entry?.confidence),
      };
    })
    .filter((entry) => entry.text.length > 0)
    .sort((a, b) => a.timestamp_seconds - b.timestamp_seconds);
}

function dedupeTexts(texts: string[]) {
  const seen = new Set<string>();
  const deduped: string[] = [];
  for (const text of texts) {
    const normalized = text.replace(/\s+/g, " ").trim();
    const key = normalized.toLowerCase();
    if (normalized.length === 0 || seen.has(key)) continue;
    seen.add(key);
    deduped.push(normalized);
  }
  return deduped;
}

function ocrTextLines(text: string): string[] {
  return text
    .split(/\n+|(?:\s{2,})/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter((line) => line.length > 1)
    .filter((line) => !/^[^\p{L}\p{N}]+$/u.test(line));
}

function normalizeOCRText(text: string): string {
  return dedupeTexts(ocrTextLines(text))
    .join(" ")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

async function transcribeAudioWithTimestamps(item: Record<string, unknown>): Promise<TranscriptSegment[] | null> {
  const audioUrl = stringValue(item.audioUrl) ?? extractVideoUrl(item, extractMediaItems(item));
  if (!audioUrl) return null;

  const audioResponse = await fetch(audioUrl);
  if (!audioResponse.ok) {
    throw new Error(`Audio download failed: ${await audioResponse.text()}`);
  }

  const audioBlob = await audioResponse.blob();
  const formData = new FormData();
  formData.append("file", audioBlob, "reel.mp4");
  formData.append("model", "whisper-1");
  formData.append("response_format", "verbose_json");
  formData.append("timestamp_granularities[]", "segment");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
    },
    body: formData,
  });

  if (!response.ok) {
    throw new Error(`OpenAI timestamp transcription failed: ${await response.text()}`);
  }

  const transcription = await response.json();
  if (!Array.isArray(transcription.segments)) return null;

  return transcription.segments
    .map((rawSegment: unknown) => {
      const segment = objectValue(rawSegment);
      return {
        start: numberValue(segment?.start) ?? 0,
        end: numberValue(segment?.end) ?? 0,
        text: textOrFallback(segment?.text, ""),
      };
    })
    .filter((segment: TranscriptSegment) => segment.text.length > 0 && segment.end > segment.start);
}

function extractTranscript(item: Record<string, unknown>) {
  const transcript = item.transcript ?? item.transcription ?? item.subtitles;
  if (!Array.isArray(transcript)) return transcript ?? null;

  return transcript.map((rawEntry) => {
    const entry = objectValue(rawEntry);
    return {
      start: numberValue(entry?.start) ?? numberValue(entry?.startTime),
      end: numberValue(entry?.end) ?? numberValue(entry?.endTime),
      text: stringValue(entry?.text) ?? stringValue(entry?.caption),
    };
  });
}

function detectSource(sourceUrl: string) {
  if (sourceUrl.includes("tiktok.com")) return "tiktok";
  return "instagram";
}

function normalizeReelUrl(value: unknown) {
  if (typeof value !== "string") throw new Error("Missing url");
  const url = new URL(value.trim());
  if (!["instagram.com", "www.instagram.com", "tiktok.com", "www.tiktok.com", "vm.tiktok.com", "vt.tiktok.com"].includes(url.hostname)) {
    throw new Error("Only Instagram and TikTok URLs are supported");
  }
  return url.toString();
}

function isInstagramPostURL(sourceUrl: string) {
  try {
    const url = new URL(sourceUrl);
    return url.hostname.includes("instagram.com") && /^\/p\//.test(url.pathname);
  } catch {
    return false;
  }
}

function profileIdFromBody(body: Record<string, unknown>) {
  return uuidText(body.profile_id, "Missing profile_id");
}

function uuidText(value: unknown, message: string) {
  if (typeof value !== "string" || !/^[0-9a-fA-F-]{36}$/.test(value)) {
    throw new Error(message);
  }
  return value;
}

function normalizeHandle(value: string) {
  const handle = value
    .trim()
    .toLowerCase()
    .replace(/^@+/, "")
    .replace(/[^a-z0-9_ .-]/g, "")
    .replace(/\s+/g, "-")
    .slice(0, 32);
  return handle.length > 0 ? handle : `user-${crypto.randomUUID().slice(0, 8)}`;
}

function normalizeNicheTags(value: unknown) {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(value.map(normalizeNicheTag).filter((tag): tag is string => !!tag))).slice(0, 8);
}

function normalizeNicheTag(value: unknown) {
  if (typeof value !== "string") return null;
  const tag = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .slice(0, 32);
  return tag.length > 0 ? tag : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function textOrFallback(value: unknown, fallback: string) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function textOrNull(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(value) : null;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? value as Record<string, unknown> : null;
}

function clampInt(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.round(value)) : fallback;
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function requiredEnv(key: string) {
  const value = Deno.env.get(key);
  if (!value) throw new Error(`Missing ${key}`);
  return value;
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  try {
    return JSON.stringify(error);
  } catch {
    return "Unexpected error";
  }
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
