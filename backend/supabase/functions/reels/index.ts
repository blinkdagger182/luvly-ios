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

type AiTab = {
  id: string;
  label: string;
};

// key-value items (quick_answer, tools, ingredients, exercises, places, etc.)
// step items use title + body + optional timestamp
type AiOverviewItem = {
  label?: string;
  value?: string;
  note?: string;
  title?: string;
  body?: string;
  timestamp?: string;
};

type AiOverviewSection = {
  id: string;
  tab_id: string;
  type: string; // "quick_answer" | "steps" | "key_points" | "tools" | "ingredients" | etc.
  title: string;
  items: AiOverviewItem[];
};

type AiOverview = {
  type: string;
  title: string;
  summary: string;
  confidence: string;
  tabs: AiTab[];
  sections: AiOverviewSection[];
};

type ReelSummary = {
  title: string;
  category: string;
  summary: string;
  segments: Segment[];
  ai_overview?: AiOverview;
};

type TranscriptSegment = {
  start: number;
  end: number;
  text: string;
};

type SignalAnalysis = {
  reelType: "ocr_led" | "audio_led" | "hybrid" | "weak";
  dominantSignal: "screen_text" | "voice" | "hybrid" | "caption" | "unknown";
  confidence: number;
  isMusicLike: boolean;
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
const googleVideoIntelligenceApiKey = Deno.env.get("GOOGLE_VIDEO_INTELLIGENCE_API_KEY") ?? "";

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

    if (request.method === "POST" && parts[parts.length - 1] === "gallery") {
      const body = await request.json();
      const profileId = uuidText(body.profile_id, "Missing profile_id");
      return json(await importGalleryReel(body, profileId), 201);
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
    .select("added_at, last_opened_at, reels(*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*))")
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
    .select("*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*)")
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

  const { count, error: countError } = await supabase
    .from("reel_profile_library")
    .select("*", { count: "exact", head: true })
    .eq("reel_id", id);

  if (countError) throw countError;

  if ((count ?? 0) === 0) {
    await supabase.from("reel_public_shares").delete().eq("reel_id", id);
    await supabase.from("reel_bookmarks").delete().eq("reel_id", id);
    await supabase.from("reel_ocr_entries").delete().eq("reel_id", id);
    await supabase.from("reel_segments").delete().eq("reel_id", id);
    await supabase.from("reels").delete().eq("id", id);
  }

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
    supabase.from("reel_friend_shares").select("*, reel:reels(*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*)), collection:reel_social_collections(*)").or(`receiver_profile_id.eq.${profileId},receiver_handle.eq.${handle}`).order("created_at", { ascending: false }).limit(30),
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
    .select("reel_id, niche_tags, share_count, save_count, view_count, shared_at, reels(*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*))")
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
      .select("id, name, created_at, reel_social_collection_items(reel_id, order_index, reels(*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*)))")
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
    .select("*, reel:reels(*, reel_segments(*), reel_ocr_entries(*), reel_transcript_segments(*)), collection:reel_social_collections(*)")
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

async function storeTranscriptSegments(reelId: string, transcript: unknown, isMusicLike: boolean) {
  if (!hasTimestampedTranscript(transcript)) return;
  const segments = transcript as TranscriptSegment[];
  await supabase.from("reel_transcript_segments").delete().eq("reel_id", reelId);
  const rows = segments
    .filter((s) => s.text.trim().length > 0 && s.end > s.start)
    .map((s) => ({
      reel_id: reelId,
      start_seconds: s.start,
      end_seconds: s.end,
      text: s.text.trim(),
      is_music_like: isMusicLike,
    }));
  if (rows.length > 0) {
    const { error } = await supabase.from("reel_transcript_segments").insert(rows);
    if (error) console.warn("Failed to store transcript segments:", error.message);
  }
}

async function updateReelOCR(id: string, rawEntries: unknown) {
  const allEntries = normalizeOCREntries(rawEntries);
  // Deduplicate: keep only the first entry per (timestamp, normalizedText) pair
  const seen = new Set<string>();
  const entries = allEntries.filter((entry) => {
    const key = `${entry.timestamp_seconds}:${normalizeOCRText(entry.text)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

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

  // Collapse OCR entries to clean visual events before sending to LLM
  const duration = clampInt(reel.duration_seconds, 60);
  const collapsedEntries = expandOCRVisualEvents(entries, duration);

  const input = {
    ...reel,
    ocr_entries: collapsedEntries,
  } as NormalizedReel;
  const signal = classifySignals(input);
  const summary = await summarizeReel(input, signal);
  const segments = normalizeSegments(summary.segments, input);

  const { error: updateError } = await supabase
    .from("reels")
    .update({
      title: summary.title,
      category: summary.category,
      summary: summary.summary,
      ai_overview: summary.ai_overview ?? null,
      reel_type: signal.reelType,
      dominant_signal: signal.dominantSignal,
      signal_confidence: signal.confidence,
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

async function regenerateAiOverview(reel: Record<string, unknown>) {
  const reelId = typeof reel.id === "string" ? reel.id : null;
  if (!reelId) return;

  const [ocrResult, transcriptResult] = await Promise.all([
    supabase.from("reel_ocr_entries").select("timestamp_seconds, text, confidence").eq("reel_id", reelId).order("timestamp_seconds"),
    supabase.from("reel_transcript_segments").select("start_seconds, end_seconds, text").eq("reel_id", reelId).order("start_seconds"),
  ]);

  const ocrEntries: OCREntry[] = (ocrResult.data ?? []).map((row: Record<string, unknown>) => ({
    timestamp_seconds: clampInt(row.timestamp_seconds, 0),
    text: textOrFallback(row.text, ""),
    confidence: numberValue(row.confidence),
  }));

  const transcript = (transcriptResult.data ?? []).map((row: Record<string, unknown>) => ({
    start: numberValue(row.start_seconds) ?? 0,
    end: numberValue(row.end_seconds) ?? 0,
    text: textOrFallback(row.text, ""),
  }));

  const input: NormalizedReel = {
    source: typeof reel.source === "string" ? reel.source : "instagram",
    source_url: typeof reel.source_url === "string" ? reel.source_url : "",
    caption: typeof reel.caption === "string" ? reel.caption : null,
    duration_seconds: typeof reel.duration_seconds === "number" ? reel.duration_seconds : null,
    video_url: typeof reel.video_url === "string" ? reel.video_url : null,
    ocr_entries: ocrEntries.length > 0 ? ocrEntries : undefined,
    transcript: transcript.length > 0 ? transcript : null,
  };

  const signal = classifySignals(input);
  const summary = await summarizeReel(input, signal).catch((err) => {
    console.warn("regenerateAiOverview: summarizeReel failed:", errorMessage(err));
    return null;
  });

  if (!summary?.ai_overview) return;

  await supabase
    .from("reels")
    .update({
      category: summary.category,
      ai_overview: summary.ai_overview,
    })
    .eq("id", reelId);
}

async function importReel(sourceUrl: string, profileId: string) {
  await ensureSocialProfile(profileId);

  const { data: existing } = await supabase
    .from("reels")
    .select("*, reel_segments(*)")
    .eq("source_url", sourceUrl)
    .maybeSingle();

  if (existing?.status === "ready") {
    const overview = existing.ai_overview as Record<string, unknown> | null;
    const needsRegen = !overview || !Array.isArray(overview.tabs) || overview.tabs.length === 0;
    if (needsRegen) {
      await regenerateAiOverview(existing);
    }
    await addReelToProfileLibrary(profileId, existing.id);
    return await getReel(existing.id);
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
    const rawDuration = numberValue(apifyItem.videoDuration) ?? numberValue((apifyItem.videoMeta as Record<string, unknown>)?.duration);
    if (source === "tiktok" && !apifyItem.isSlideshow && rawDuration !== null && rawDuration > 90) {
      throw new Error("TikTok videos over 90 seconds are not supported.");
    }
    const normalized = await normalizeApifyItem(sourceUrl, apifyItem);
    const signal = classifySignals(normalized);
    const summary = await summarizeReel(normalized, signal);

    const needsVisualOCR = hasVideoURL(normalized) || (Array.isArray(normalized.media_items) && normalized.media_items.length > 0);
    const hasServerOCR = hasOCREntries(normalized.ocr_entries);
    const { ocr_entries: _ocr, detected_language: _lang, ...reelColumns } = normalized;
    const { data: reel, error: updateError } = await supabase
      .from("reels")
      .update({
        ...reelColumns,
        title: summary.title,
        category: summary.category,
        summary: summary.summary,
        ai_overview: summary.ai_overview ?? null,
        raw_payload: apifyItem,
        reel_type: signal.reelType,
        dominant_signal: signal.dominantSignal,
        signal_confidence: signal.confidence,
        status: needsVisualOCR && !hasServerOCR ? "ready_basic" : "ready",
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

    if (hasServerOCR && Array.isArray(normalized.ocr_entries) && normalized.ocr_entries.length > 0) {
      const { error: ocrError } = await supabase.from("reel_ocr_entries").insert(
        normalized.ocr_entries.map((entry) => ({
          reel_id: created.id,
          timestamp_seconds: entry.timestamp_seconds,
          text: entry.text,
          confidence: entry.confidence ?? null,
        })),
      );
      if (ocrError) console.warn("Failed to store server OCR entries:", ocrError.message);
    }

    await storeTranscriptSegments(created.id, normalized.transcript, signal.isMusicLike);

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

async function importGalleryReel(body: Record<string, unknown>, profileId: string) {
  await ensureSocialProfile(profileId);
  const videoUrl = typeof body.video_url === "string" && body.video_url.length > 0 ? body.video_url : null;
  const title = textOrFallback(body.title, "My Reel");
  const duration = numberValue(body.duration_seconds);

  const { data: created, error } = await supabase
    .from("reels")
    .insert({
      source: "gallery",
      source_url: videoUrl ?? `gallery:${crypto.randomUUID()}`,
      video_url: videoUrl,
      title,
      duration_seconds: duration,
      status: videoUrl ? "ready_basic" : "ready",
      category: "general",
      summary: "",
    })
    .select()
    .single();

  if (error) throw error;
  await addReelToProfileLibrary(profileId, created.id);
  return await getReel(created.id);
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
      shouldDownloadVideos: true,
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
  const extractedVideoUrl = extractVideoUrl(item, mediaItems);
  const isSlideshow = isLikelySlideshow(item, mediaItems);
  const rawVideoUrl = isSlideshow ? null : (extractedVideoUrl ? withApifyToken(extractedVideoUrl) : null);
  const reelIdForStorage = stringValue(item.id) ?? stringValue(item.shortCode) ?? stringValue(item.awemeId) ?? crypto.randomUUID();
  const videoUrl = rawVideoUrl?.includes("api.apify.com")
    ? await reuploadVideoToStorage(rawVideoUrl, reelIdForStorage)
    : rawVideoUrl;
  const owner = objectValue(item.owner);
  const author = objectValue(item.authorMeta) ?? objectValue(item.author);
  const caption = stringValue(item.caption) ?? stringValue(item.text) ?? stringValue(item.description);
  const duration = numberValue(item.videoDuration) ??
    numberValue(item.duration) ??
    numberValue(item.durationSeconds) ??
    numberValue(objectValue(item.videoMeta)?.duration) ??
    slideshowDuration(mediaItems);

  const shouldTranscribeAudio = typeof videoUrl === "string" && videoUrl.length > 0;
  const shouldRunVideoOCR = typeof videoUrl === "string" && videoUrl.length > 0 && !isSlideshow;

  // Run Whisper first so we can pass the detected language to Google Video Intelligence OCR
  let detectedLanguage: string | null = null;
  if (shouldTranscribeAudio && !hasTimestampedTranscript(transcript)) {
    const transcriptResult = await transcribeAudioWithTimestamps(item).catch((error) => {
      console.warn("Skipping timestamp transcription:", errorMessage(error));
      return null;
    });
    if (transcriptResult !== null) {
      transcript = transcriptResult.segments;
      detectedLanguage = transcriptResult.language;
      console.log(`Detected language: ${detectedLanguage ?? "unknown"}`);
    }
  }

  // Build language hints from detected language — always include "en" as fallback for mixed-language content
  const ocrLanguageHints = detectedLanguage && detectedLanguage !== "en"
    ? [detectedLanguage, "en"]
    : [];

  const videoOcrEntries = shouldRunVideoOCR
    ? await runVideoIntelligenceOCR(videoUrl!, duration, ocrLanguageHints).catch((error) => {
        console.warn("Skipping video OCR:", errorMessage(error));
        return [] as OCREntry[];
      })
    : [] as OCREntry[];

  const ocrEntries = videoOcrEntries.length > 0
    ? videoOcrEntries
    : (mediaItems.length > 0 && !videoUrl ? mediaItemsToOCREntries(mediaItems, caption) : undefined);

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
    detected_language: detectedLanguage,
  };
}

function scoreOCR(entries: OCREntry[] | undefined): number {
  if (!hasOCREntries(entries)) return 0;
  const events = expandOCRVisualEvents(entries!, 9999);
  const meaningful = events.filter((e) => meaningfulOCRText(e.text).length > 0);
  if (meaningful.length >= 4) return 0.9;
  if (meaningful.length >= 2) return 0.6;
  if (meaningful.length === 1) return 0.3;
  return 0;
}

function scoreAudio(transcript: unknown): { score: number; isMusicLike: boolean } {
  if (!hasTimestampedTranscript(transcript)) {
    const text = transcriptText(transcript);
    if (text.trim().split(/\s+/).length < 10) return { score: 0, isMusicLike: false };
    return { score: 0.4, isMusicLike: false };
  }
  const segments = transcript as TranscriptSegment[];
  const totalWords = segments.reduce((sum, s) => sum + s.text.trim().split(/\s+/).length, 0);
  if (totalWords < 5) return { score: 0, isMusicLike: false };
  const avgWordsPerSeg = totalWords / segments.length;
  const avgDuration = segments.reduce((sum, s) => sum + (s.end - s.start), 0) / segments.length;
  const shortFraction = segments.filter((s) => s.text.trim().split(/\s+/).length <= 4).length / segments.length;
  const isMusicLike = shortFraction > 0.7 && avgDuration < 2.5 && segments.length > 8;
  if (isMusicLike) return { score: 0.1, isMusicLike: true };
  if (totalWords >= 50 && avgWordsPerSeg >= 5) return { score: 0.9, isMusicLike: false };
  if (totalWords >= 20) return { score: 0.6, isMusicLike: false };
  return { score: 0.3, isMusicLike: false };
}

function classifySignals(input: NormalizedReel): SignalAnalysis {
  const ocrScore = scoreOCR(input.ocr_entries);
  const { score: audioScore, isMusicLike } = scoreAudio(input.transcript);
  const HIGH = 0.6;
  if (ocrScore >= HIGH && audioScore >= HIGH) {
    return { reelType: "hybrid", dominantSignal: "hybrid", confidence: Math.max(ocrScore, audioScore), isMusicLike };
  }
  if (ocrScore >= HIGH) {
    return { reelType: "ocr_led", dominantSignal: "screen_text", confidence: ocrScore, isMusicLike };
  }
  if (audioScore >= HIGH) {
    return { reelType: "audio_led", dominantSignal: "voice", confidence: audioScore, isMusicLike };
  }
  const hasCaption = typeof input.caption === "string" && input.caption.trim().length > 30;
  if (hasCaption) {
    return { reelType: "weak", dominantSignal: "caption", confidence: 0.3, isMusicLike };
  }
  return { reelType: "weak", dominantSignal: "unknown", confidence: 0.1, isMusicLike };
}

function signalRoutingInstruction(signal: SignalAnalysis | undefined): string {
  const type = signal?.reelType ?? "weak";
  switch (type) {
    case "ocr_led":
      return "On-screen text (ocr_entries) is the primary signal. Use OCR text changes as hard segment boundaries and titles. Do NOT use audio transcript timestamps as segment boundaries — the audio may be background music or song lyrics. Use transcript only to enrich descriptions where the creator is clearly speaking instructions.";
    case "audio_led":
      return "Audio transcript is the primary signal. Use transcript timestamps for segment boundaries. Use OCR entries only for additional context or titles when present.";
    case "hybrid":
      return "Both screen text and audio are strong signals. Use OCR text changes for segment boundaries and titles. Use transcript content to enrich step descriptions with what the creator said.";
    case "weak":
    default:
      return "Signal quality is low — no reliable OCR or speech detected. Generate a minimal summary from caption or title. Do not invent precise steps. Prefer a single broad segment over fabricated detail.";
  }
}

const INTENT_TYPES = [
  "recipe",
  "workout",
  "travel",
  "food_guide",
  "tutorial",
  "ai_tool",
  "study",
  "beauty",
  "fashion",
  "tech",
  "diy",
  "finance",
  "business",
  "product_review",
  "language",
  "motivation",
  "news",
  "general",
] as const;

const INTENT_TYPE_GUIDE = `
Choose the single best category from this list:
- recipe: cooking, baking, food preparation with ingredients and steps
- workout: fitness, exercise routines, gym movements, sport drills
- travel: destinations, itineraries, places to visit, trip vlogs
- food_guide: restaurant reviews, food spots, where to eat, best dishes
- tutorial: how-to, step-by-step skills, creative techniques, video editing, photography
- ai_tool: AI tools, voice cloning, image generators, chatbots, automation tools, AI workflows
- study: study tips, productivity systems, note-taking, Pomodoro, academic advice
- beauty: skincare routines, makeup tutorials, haircare, product application order
- fashion: outfit ideas, style guides, lookbooks, clothing hauls
- tech: coding tutorials, software setup, developer tools, programming (non-AI)
- diy: home improvement, crafts, repairs, building projects
- finance: money tips, budgeting, investing, tax advice, side hustles
- business: marketing tactics, creator strategies, entrepreneur advice, growth tips
- product_review: gadget/product reviews, comparisons, pros and cons, verdicts
- language: language learning, phrases, vocabulary, pronunciation guides
- motivation: self-improvement, mindset, life advice, inspirational quotes
- news: news explainers, current events, analysis, briefings
- general: does not fit any specific category above (memes, entertainment, lifestyle, etc.)`.trim();

// Section schema per category. Each section must have: id, tab_id, type, title, items.
// Step items use: { title, body, timestamp? }
// Key-value items use: { label, value?, note? }
const AI_OVERVIEW_SECTION_SCHEMAS: Record<string, string> = {
  recipe: `tabs: [{"id":"guide","label":"Recipe"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Dish", value:"name"},{label:"Prep time", value:"X min"},{label:"Cook time", value:"X min"},{label:"Difficulty", value:"Easy|Medium|Hard"}]}
- {id:"ingredients", tab_id:"guide", type:"ingredients", title:"Ingredients", items:[{label:"ingredient", value:"quantity", note?:"prep note"}]}
- {id:"steps", tab_id:"guide", type:"steps", title:"Steps", items:[{title:"step name", body:"instruction", timestamp?:"0:00"}]}
- {id:"substitutions", tab_id:"guide", type:"key_points", title:"Substitutions", items:[{label:"original", value:"substitute"}]}`,

  workout: `tabs: [{"id":"guide","label":"Workout"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Workout type", value:"..."},{label:"Target muscles", value:"..."},{label:"Duration", value:"X min"},{label:"Equipment", value:"..."}]}
- {id:"exercises", tab_id:"guide", type:"exercises", title:"Exercises", items:[{label:"exercise name", value:"sets x reps", note?:"muscle group"}]}
- {id:"form_cues", tab_id:"guide", type:"key_points", title:"Form Cues", items:[{label:"exercise", value:"cue"}]}
- {id:"mistakes", tab_id:"guide", type:"key_points", title:"Mistakes to Avoid", items:[{label:"mistake", value:"correction"}]}`,

  travel: `tabs: [{"id":"places","label":"Places"},{"id":"itinerary","label":"Itinerary"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"places", type:"quick_answer", title:"Quick Answer", items:[{label:"Destination", value:"..."},{label:"Vibe", value:"romantic|budget|luxury|hidden gem|family"},{label:"Best for", value:"..."}]}
- {id:"places", tab_id:"places", type:"places", title:"Places", items:[{label:"place name", value:"type (cafe/attraction/area)", note?:"tip or why visit"}]}
- {id:"itinerary", tab_id:"itinerary", type:"steps", title:"Itinerary", items:[{title:"Day 1 / Morning / etc.", body:"plan summary"}]}
- {id:"tips", tab_id:"places", type:"key_points", title:"Tips", items:[{label:"tip", value:"advice"}]}`,

  food_guide: `tabs: [{"id":"guide","label":"Guide"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"spots", tab_id:"guide", type:"places", title:"Food Spots", items:[{label:"place name", value:"location or cuisine", note?:"must-order dish"}]}
- {id:"dishes", tab_id:"guide", type:"ingredients", title:"Dishes to Try", items:[{label:"dish name", value:"price range", note?:"description"}]}
- {id:"tips", tab_id:"guide", type:"key_points", title:"Tips", items:[{label:"tip", value:"advice"}]}`,

  tutorial: `tabs: [{"id":"guide","label":"Guide"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Goal", value:"what you will achieve"},{label:"Best for", value:"who this suits"},{label:"Skill level", value:"beginner|intermediate|advanced"}]}
- {id:"steps", tab_id:"guide", type:"steps", title:"Steps", items:[{title:"step name", body:"action", timestamp?:"0:00"}]}
- {id:"tools", tab_id:"guide", type:"key_points", title:"Tools & Materials", items:[{label:"tool", value?:"purpose or spec"}]}
- {id:"warnings", tab_id:"guide", type:"key_points", title:"Warnings", items:[{label:"warning", value:"what to avoid"}]}`,

  ai_tool: `tabs: [{"id":"guide","label":"Guide"},{"id":"tools","label":"Tools"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Goal", value:"what this tool/workflow achieves"},{label:"Tool mentioned", value:"specific tool name"},{label:"Best for", value:"who benefits from this"}]}
- {id:"steps", tab_id:"guide", type:"steps", title:"Steps", items:[{title:"step name", body:"concrete action — be specific, not generic", timestamp?:"0:00"}]}
- {id:"tools", tab_id:"tools", type:"key_points", title:"Tools", items:[{label:"tool name", value:"what it does", note?:"free/paid or link if mentioned"}]}
- {id:"tips", tab_id:"tools", type:"key_points", title:"Tips", items:[{label:"tip", value:"advice"}]}`,

  study: `tabs: [{"id":"guide","label":"Study Notes"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Main advice", value:"..."},{label:"Best for", value:"..."},{label:"Time needed", value?:"..."}]}
- {id:"advice", tab_id:"guide", type:"steps", title:"Key Advice", items:[{title:"tip name", body:"explanation"}]}
- {id:"tools", tab_id:"guide", type:"key_points", title:"Tools Mentioned", items:[{label:"tool", value?:"how to use"}]}
- {id:"routine", tab_id:"guide", type:"key_points", title:"Routine", items:[{label:"time slot or phase", value:"activity"}]}`,

  beauty: `tabs: [{"id":"routine","label":"Routine"},{"id":"products","label":"Products"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"routine", type:"quick_answer", title:"Quick Answer", items:[{label:"Skin type", value:"..."},{label:"Routine", value:"morning|night|both"},{label:"Duration", value:"X min"}]}
- {id:"steps", tab_id:"routine", type:"steps", title:"Steps", items:[{title:"step name", body:"action", timestamp?:"0:00"}]}
- {id:"products", tab_id:"products", type:"ingredients", title:"Products", items:[{label:"product name", value?:"brand", note?:"skin type suitability"}]}
- {id:"tips", tab_id:"routine", type:"key_points", title:"Tips", items:[{label:"tip", value:"advice"}]}`,

  fashion: `tabs: [{"id":"guide","label":"Outfit"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Style", value:"..."},{label:"Occasion", value:"..."},{label:"Color palette", value:"..."}]}
- {id:"items", tab_id:"guide", type:"ingredients", title:"Outfit Items", items:[{label:"clothing item", value?:"brand or style", note?:"color or fit"}]}
- {id:"styling", tab_id:"guide", type:"key_points", title:"Styling Tips", items:[{label:"rule or tip", value:"how to apply"}]}`,

  tech: `tabs: [{"id":"guide","label":"Dev Guide"},{"id":"tools","label":"Stack"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Problem solved", value:"..."},{label:"Language/framework", value:"..."},{label:"Skill level", value:"beginner|intermediate|advanced"}]}
- {id:"steps", tab_id:"guide", type:"steps", title:"Steps", items:[{title:"step name", body:"action", timestamp?:"0:00"}]}
- {id:"stack", tab_id:"tools", type:"key_points", title:"Tech Stack", items:[{label:"technology", value:"purpose"}]}
- {id:"gotchas", tab_id:"guide", type:"key_points", title:"Gotchas", items:[{label:"issue", value:"fix or workaround"}]}`,

  diy: `tabs: [{"id":"guide","label":"Project"},{"id":"materials","label":"Materials"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Goal", value:"..."},{label:"Difficulty", value:"Easy|Medium|Hard"},{label:"Est. cost", value?:"..."},{label:"Time", value?:"..."}]}
- {id:"steps", tab_id:"guide", type:"steps", title:"Steps", items:[{title:"step name", body:"action", timestamp?:"0:00"}]}
- {id:"materials", tab_id:"materials", type:"ingredients", title:"Materials", items:[{label:"material", value?:"quantity or spec"}]}
- {id:"tools", tab_id:"materials", type:"key_points", title:"Tools", items:[{label:"tool", value?:"purpose"}]}`,

  finance: `tabs: [{"id":"guide","label":"Key Points"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Main idea", value:"..."},{label:"Who it applies to", value:"..."},{label:"Risk level", value:"Low|Medium|High"}]}
- {id:"ideas", tab_id:"guide", type:"steps", title:"Key Ideas", items:[{title:"concept name", body:"explanation"}]}
- {id:"actions", tab_id:"guide", type:"key_points", title:"Action Steps", items:[{label:"action", value:"how to do it"}]}
- {id:"disclaimers", tab_id:"guide", type:"key_points", title:"Disclaimers", items:[{label:"risk or caveat", value:"note"}]}`,

  business: `tabs: [{"id":"guide","label":"Strategy"},{"id":"tools","label":"Tools"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Main tactic", value:"..."},{label:"Why it works", value:"..."},{label:"Best for", value:"..."}]}
- {id:"tactics", tab_id:"guide", type:"steps", title:"How to Apply", items:[{title:"step name", body:"action"}]}
- {id:"tools", tab_id:"tools", type:"key_points", title:"Tools Mentioned", items:[{label:"tool", value?:"use case"}]}
- {id:"examples", tab_id:"guide", type:"key_points", title:"Examples", items:[{label:"example", value:"detail"}]}`,

  product_review: `tabs: [{"id":"guide","label":"Review"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"quick_answer", tab_id:"guide", type:"quick_answer", title:"Quick Answer", items:[{label:"Product", value:"..."},{label:"Price", value?:"..."},{label:"Who it's for", value:"..."},{label:"Verdict", value:"Recommended|Not recommended|Mixed"}]}
- {id:"pros", tab_id:"guide", type:"key_points", title:"Pros", items:[{label:"pro", value?:"detail"}]}
- {id:"cons", tab_id:"guide", type:"key_points", title:"Cons", items:[{label:"con", value?:"detail"}]}
- {id:"alternatives", tab_id:"guide", type:"key_points", title:"Alternatives", items:[{label:"alternative", value?:"comparison note"}]}`,

  language: `tabs: [{"id":"phrases","label":"Phrases"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"phrases", tab_id:"phrases", type:"ingredients", title:"Phrases", items:[{label:"phrase (target language)", value:"English translation", note?:"pronunciation"}]}
- {id:"examples", tab_id:"phrases", type:"key_points", title:"Example Sentences", items:[{label:"phrase", value:"example sentence"}]}`,

  motivation: `tabs: [{"id":"guide","label":"Insights"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"message", tab_id:"guide", type:"quick_answer", title:"Core Message", items:[{label:"Main point", value:"..."},{label:"Applies to", value:"..."}]}
- {id:"quotes", tab_id:"guide", type:"key_points", title:"Key Quotes", items:[{label:"quote", value?:"context"}]}
- {id:"actions", tab_id:"guide", type:"steps", title:"Takeaways", items:[{title:"action", body:"how to apply"}]}`,

  news: `tabs: [{"id":"guide","label":"Briefing"},{"id":"context","label":"Context"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"summary", tab_id:"guide", type:"quick_answer", title:"What Happened", items:[{label:"Event", value:"..."},{label:"Where", value?:"..."},{label:"When", value?:"..."}]}
- {id:"timeline", tab_id:"context", type:"steps", title:"Timeline", items:[{title:"date or event", body:"what happened"}]}
- {id:"people", tab_id:"context", type:"key_points", title:"Key People & Orgs", items:[{label:"name", value:"role"}]}
- {id:"context", tab_id:"context", type:"key_points", title:"Background", items:[{label:"context point", value:"explanation"}]}`,

  general: `tabs: [{"id":"guide","label":"Summary"},{"id":"transcript","label":"Voice"},{"id":"screen_text","label":"Screen"}]
sections:
- {id:"key_points", tab_id:"guide", type:"steps", title:"Key Points", items:[{title:"point", body:"explanation"}]}`,
};

async function summarizeReel(input: Record<string, unknown>, signal?: SignalAnalysis): Promise<ReelSummary> {
  const detectedLanguage = typeof input.detected_language === "string" ? input.detected_language : null;
  const languageLine = detectedLanguage && detectedLanguage !== "en"
    ? `The audio language was detected as "${detectedLanguage}". Transcript text may be in this language. Use the original language for raw_text; translate titles and descriptions to English.`
    : "If transcript or caption is non-English, use the original language for raw_text and translate to English for title and description.";

  const allSchemasText = Object.entries(AI_OVERVIEW_SECTION_SCHEMAS)
    .map(([type, schema]) => `If category="${type}":\n${schema}`)
    .join("\n\n");

  const promptContent = [
    "Convert this short-form video into a structured note. Return strict JSON with these top-level keys: title, category, summary, segments, ai_overview.",
    "",
    "=== SEGMENTS ===",
    "Each segment: start_seconds (int), end_seconds (int), title, description, raw_text, tags. Cover reel in order. No null values.",
    "Base every segment strictly on evidence in transcript/ocr_entries/caption/media_items. Do NOT invent step names.",
    signalRoutingInstruction(signal),
    "For image slideshows (media_items present, no video_url): use synthetic timestamps and per-slide visual text for segments.",
    languageLine,
    "Return one segment per distinct visual state for list/place content (up to 20). For narrative content, 4–8 high-signal segments.",
    "",
    "=== CATEGORY ===",
    `The category field must be exactly one of: ${INTENT_TYPES.join(", ")}.`,
    INTENT_TYPE_GUIDE,
    "",
    "=== AI OVERVIEW ===",
    "The ai_overview field is a structured note tailored to the category.",
    "CRITICAL RULES:",
    "1. Every item must contain ONLY content that appears in the actual input data (transcript, OCR, caption). Never invent, infer, or pad.",
    "2. Steps items use {title, body, timestamp?} — title is the step name, body is the specific concrete action extracted from the content, timestamp is 'M:SS' format if the moment appears in the transcript or OCR.",
    "3. Key-value items use {label, value?, note?} — label is the field name, value is the extracted content.",
    "4. If a section has no evidenced items, omit it entirely. Do not write placeholder text.",
    "5. Steps body must describe a SPECIFIC ACTION, not a summary. Bad: 'Voice cloning technology allows...' Good: 'Upload 3+ minutes of clear audio samples to the tool'.",
    "6. ai_overview.summary must be 2-3 sentences answering: what is this reel about, what can the viewer do with it.",
    "ai_overview schema: { type, title, summary, confidence:'high'|'medium'|'low', tabs:[{id,label}], sections:[{id, tab_id, type, title, items:[...]}] }",
    "confidence: 'high' if OCR or transcript strongly support the output, 'medium' if mainly caption-based, 'low' if thin signal.",
    "",
    "Section schema for the detected category (use ONLY sections/items evidenced in the input):",
    allSchemasText,
    "",
    "=== INPUT DATA ===",
    JSON.stringify(input),
  ].join("\n");

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
          content: "You are a structured content extractor for a reel-saving app. Extract only what is explicitly present in the input data. Respond with valid JSON only. Never invent content or write generic summaries — every item must trace back to a specific moment in the transcript, OCR, or caption.",
        },
        { role: "user", content: promptContent },
      ],
      response_format: { type: "json_object" },
      temperature: 0.1,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI summary failed: ${await response.text()}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  const parsed = JSON.parse(content) as ReelSummary & { ai_overview?: AiOverview };

  const rawCategory = typeof parsed.category === "string" ? parsed.category.toLowerCase().trim().replace(/[^a-z_]/g, "").replace(/\s+/g, "_") : "";
  const category = (INTENT_TYPES as readonly string[]).includes(rawCategory) ? rawCategory : "general";

  const ai_overview = normalizeAiOverview(parsed.ai_overview, category);

  return {
    title: parsed.title || "Saved reel",
    category,
    summary: parsed.summary || "",
    segments: Array.isArray(parsed.segments) ? parsed.segments : [],
    ai_overview,
  };
}

function normalizeAiOverview(raw: unknown, category: string): AiOverview | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const obj = raw as Record<string, unknown>;

  const sections: AiOverviewSection[] = [];
  if (Array.isArray(obj.sections)) {
    for (const rawSection of obj.sections) {
      const s = rawSection as Record<string, unknown>;
      const sectionType = typeof s.type === "string" ? s.type.trim() : "key_points";
      const tabId = typeof s.tab_id === "string" ? s.tab_id.trim() : "guide";
      const items: AiOverviewItem[] = [];
      if (Array.isArray(s.items)) {
        for (const rawItem of s.items) {
          const it = rawItem as Record<string, unknown>;
          const item: AiOverviewItem = {};
          // step format
          if (typeof it.title === "string" && it.title.trim()) item.title = it.title.trim();
          if (typeof it.body === "string" && it.body.trim()) item.body = it.body.trim();
          if (typeof it.timestamp === "string" && it.timestamp.trim()) item.timestamp = it.timestamp.trim();
          // key-value format
          if (typeof it.label === "string" && it.label.trim()) item.label = it.label.trim();
          if (typeof it.value === "string" && it.value.trim()) item.value = it.value.trim();
          if (typeof it.note === "string" && it.note.trim()) item.note = it.note.trim();
          // must have at least one meaningful field
          if (!item.title && !item.label) continue;
          items.push(item);
        }
      }
      if (items.length === 0) continue;
      sections.push({
        id: typeof s.id === "string" ? s.id : "section",
        tab_id: tabId,
        type: sectionType,
        title: typeof s.title === "string" ? s.title : "Section",
        items,
      });
    }
  }

  if (sections.length === 0) return undefined;

  const tabs: AiTab[] = [];
  if (Array.isArray(obj.tabs)) {
    for (const rawTab of obj.tabs) {
      const t = rawTab as Record<string, unknown>;
      if (typeof t.id === "string" && typeof t.label === "string") {
        tabs.push({ id: t.id.trim(), label: t.label.trim() });
      }
    }
  }
  // fallback tabs if LLM omitted them
  if (tabs.length === 0) {
    const aiTabId = "guide";
    tabs.push({ id: aiTabId, label: "Guide" }, { id: "transcript", label: "Voice" }, { id: "screen_text", label: "Screen" });
  }

  return {
    type: category,
    title: typeof obj.title === "string" ? obj.title.trim() : "",
    summary: typeof obj.summary === "string" ? obj.summary.trim() : "",
    confidence: ["high", "medium", "low"].includes(obj.confidence as string) ? (obj.confidence as string) : "medium",
    tabs,
    sections,
  };
}

function normalizeSegments(rawSegments: unknown[], input: NormalizedReel): Segment[] {
  const duration = clampInt(input.duration_seconds, 60);
  const segments = rawSegments
    .map((rawSegment, index) => normalizeSegment(rawSegment, index, duration))
    .filter((segment) => segment.description.length > 0 || segment.raw_text);

  // LLM is authoritative. fallbackSegments (which calls fallbackOCRSegments) is the true fallback.
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

function levenshteinSimilarity(a: string, b: string): number {
  if (a === b) return 1;
  const la = a.length, lb = b.length;
  if (la === 0 || lb === 0) return 0;
  const prev = Array.from({ length: lb + 1 }, (_, i) => i);
  const curr = new Array<number>(lb + 1);
  for (let i = 1; i <= la; i++) {
    curr[0] = i;
    for (let j = 1; j <= lb; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    prev.splice(0, prev.length, ...curr);
  }
  return 1 - prev[lb] / Math.max(la, lb);
}

function ocrKeysSameEvent(a: string, b: string): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  // containment: one is a noisy superset of the other (e.g. "L11 SAGRADA FAMILIA" ⊇ "SAGRADA FAMILIA")
  if (a.includes(b) || b.includes(a)) return true;
  if (Math.min(a.length, b.length) < 4) return false;
  // edit-distance similarity — handles OCR misreads like "IMPARK GUELL" vs "PARK GUELL"
  return levenshteinSimilarity(a, b) >= 0.75;
}

function expandOCRVisualEvents(entries: OCREntry[], duration: number): OCREntry[] {
  if (entries.length === 0) return [];

  // Group consecutive entries into runs — maximal sequences of similar visual content.
  // Transition frame artifacts (partial/garbled text mid-animation) appear in exactly 1 sample
  // at 0.5s sampling; real text states appear in ≥2 consecutive samples.
  const runs: { entries: OCREntry[]; key: string }[] = [];
  for (const entry of entries) {
    const meaningfulText = meaningfulOCRText(entry.text);
    const key = normalizeOCRText(meaningfulText);
    if (!key) continue;
    const lastRun = runs[runs.length - 1];
    if (lastRun && ocrKeysSameEvent(key, lastRun.key)) {
      lastRun.entries.push(entry);
    } else {
      runs.push({ entries: [entry], key });
    }
  }

  // Require ≥2 consecutive samples OR be a distinct entry to survive.
  // 1-sample runs that are content-similar to either adjacent run are transition artifacts
  // (partial/garbled reads mid-animation) — kill those only.
  // 1-sample runs that are distinct from both neighbors are real brief content — keep.
  const stableRuns = runs.filter((run, index) => {
    if (run.entries.length >= 2) return true;
    if (index === 0 || index === runs.length - 1) return true;
    const prevKey = runs[index - 1]?.key ?? "";
    const nextKey = runs[index + 1]?.key ?? "";
    return !ocrKeysSameEvent(run.key, prevKey) && !ocrKeysSameEvent(run.key, nextKey);
  });

  if (stableRuns.length === 0) return entries;

  // Per run: pick canonical entry by highest confidence, then shortest normalized text (least OCR noise).
  const collapsed = stableRuns.map((run) => {
    const best = run.entries.reduce((bestEntry, e) => {
      const eConf = e.confidence ?? -1;
      const bestConf = bestEntry.confidence ?? -1;
      if (eConf > bestConf) return e;
      if (eConf === bestConf) {
        return normalizeOCRText(e.text).length < normalizeOCRText(bestEntry.text).length ? e : bestEntry;
      }
      return bestEntry;
    });
    const meaningfulText = meaningfulOCRText(best.text);
    return { ...best, text: meaningfulText || best.text };
  });

  // Remove adjacent duplicates that survived canonical selection.
  const deduped = collapsed.filter((entry, index) => {
    if (index === 0) return true;
    return !ocrKeysSameEvent(normalizeOCRText(entry.text), normalizeOCRText(collapsed[index - 1].text));
  });

  // Expand multi-line entries for carousels/slideshows (existing behaviour).
  const expanded: OCREntry[] = [];
  for (const entry of deduped) {
    const lines = ocrTextLines(entry.text);
    const shouldSplitLines = deduped.length <= 2 && lines.length >= 2;
    if (!shouldSplitLines) {
      expanded.push({ ...entry, text: lines.join(" ") || entry.text });
      continue;
    }
    lines.slice(0, 8).forEach((line, lineIndex) => {
      expanded.push({
        ...entry,
        timestamp_seconds: Math.min(duration - 1, entry.timestamp_seconds + lineIndex),
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
    item.video,
    videoMeta?.downloadAddr,
    videoMeta?.playAddr,
    videoMeta?.url,
    ...mediaItems.filter((mediaItem) => mediaItem.type === "video").map((mediaItem) => mediaItem.url),
    item.webVideoUrl,
  ];

  return urls.map(stringValue).find((url) => !!url && isPlayableVideoURL(url)) ?? null;
}

function isPlayableVideoURL(url: string): boolean {
  return /\.(mp4|mov|m3u8|webm|ts)(?:[?#].*)?$/i.test(url) ||
    /\b(cdninstagram|tiktokcdn|fbcdn|scontent|akamaized|cloudfront)\b/.test(url) ||
    url.includes("api.apify.com/v2/key-value-stores");
}

function withApifyToken(url: string): string {
  if (!url.includes("api.apify.com/v2/key-value-stores")) return url;
  return url.includes("?") ? `${url}&token=${apifyToken}` : `${url}?token=${apifyToken}`;
}

async function reuploadVideoToStorage(apifyUrl: string, reelId: string): Promise<string> {
  const response = await fetch(apifyUrl);
  if (!response.ok) return apifyUrl;

  const blob = await response.blob();
  const path = `${reelId}/video.mp4`;

  const { error } = await supabase.storage
    .from("reel-videos")
    .upload(path, blob, { contentType: "video/mp4", upsert: true });

  if (error) return apifyUrl;

  const { data } = supabase.storage.from("reel-videos").getPublicUrl(path);
  return data.publicUrl;
}

function isWebPageURL(url: string): boolean {
  return /instagram\.com\/(p|reel|stories|tv)\//i.test(url) ||
    /tiktok\.com\/@[^/]+\/video\//i.test(url) ||
    /tiktok\.com\/t\//i.test(url);
}

function isLikelySlideshow(item: Record<string, unknown>, mediaItems: MediaItem[]) {
  const explicitType = [
    item.type,
    item.mediaType,
    item.media_type,
    item.productType,
    item.product_type,
    item.awemeType,
  ]
    .map(stringValue)
    .filter((value): value is string => !!value)
    .join(" ")
    .toLowerCase();

  if (/\b(slideshow|carousel|photo|image)\b/.test(explicitType)) return true;

  const imageCount = mediaItems.filter((item) => item.type === "image").length;
  const videoCount = mediaItems.filter((item) => item.type === "video").length;
  if (imageCount >= 2 && videoCount === 0) return true;

  const knownSlideshowFields = [
    item.images,
    item.imageUrls,
    item.image_urls,
    item.slideshowImageLinks,
    item.slideshowImages,
    item.carouselMedia,
    item.carousel_media,
    item.childPosts,
    item.children,
  ];

  return knownSlideshowFields.some((value) => Array.isArray(value) && value.length >= 2);
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
  appendMediaItems(mediaItems, item.slideshowImageLinks);
  appendMediaItems(mediaItems, item.slideshowImages);
  appendMediaItems(mediaItems, item.carouselMedia);
  appendMediaItems(mediaItems, item.carousel_media);
  appendMediaItems(mediaItems, item.childPosts);
  appendMediaItems(mediaItems, item.children);
  // Only fall back to flat image lists when no richer source populated items above
  if (mediaItems.length === 0) {
    appendMediaItems(mediaItems, item.images);
    appendMediaItems(mediaItems, item.imageUrls);
    appendMediaItems(mediaItems, item.image_urls);
  }

  if (mediaItems.length === 0) {
    const imagePostUrl = stringValue(item.displayUrl) ?? stringValue(item.imageUrl) ?? stringValue(item.image_url);
    const hasVideo = !!(stringValue(item.videoUrl) ?? stringValue(item.video_url));
    if (imagePostUrl && !hasVideo) {
      mediaItems.push({
        type: "image",
        url: imagePostUrl,
        thumbnail_url: imagePostUrl,
        order_index: 0,
      });
    }
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
    const rawUrl = stringValue(item.url);
    const explicitType = stringValue(item.type) ?? stringValue(item.mediaType) ?? stringValue(item.media_type);
    const isVideoItem = explicitType?.toLowerCase().includes("video") ?? false;
    const url = (rawUrl && !isWebPageURL(rawUrl) ? rawUrl : null) ??
      stringValue(item.src) ??
      (isVideoItem ? (stringValue(item.videoUrl) ?? stringValue(item.video_url)) : null) ??
      stringValue(item.displayUrl) ??
      stringValue(item.imageUrl) ??
      stringValue(item.image_url) ??
      stringValue(item.videoUrl) ??
      stringValue(item.video_url) ??
      stringValue(item.tiktokLink) ??
      stringValue(item.downloadLink) ??
      stringValue(videoMeta?.downloadAddr) ??
      stringValue(videoMeta?.playAddr);
    if (!url) continue;

    const thumbnail = stringValue(item.thumbnailUrl) ??
      stringValue(item.thumbnail) ??
      stringValue(item.displayUrl) ??
      stringValue(item.coverUrl) ??
      stringValue(videoMeta?.coverUrl) ??
      (inferMediaType(url) === "image" ? url : null);
    output.push({
      type: isVideoItem || explicitType?.toLowerCase().includes("video") ? "video" : inferMediaType(url),
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

function meaningfulOCRText(text: string): string {
  return dedupeTexts(ocrTextLines(text))
    .filter(isMeaningfulOCRLine)
    .join("\n");
}

function isMeaningfulOCRLine(line: string): boolean {
  const normalized = line.replace(/\s+/g, " ").trim();
  const lowercased = normalized.toLowerCase();

  if (!/\p{L}/u.test(normalized)) return false;
  if (normalized.length < 3) return false;
  if (/^@[\w.]{1,24}$/.test(normalized)) return false;
  if (/^\d{1,2}:\d{2}(?::\d{2})?$/.test(normalized)) return false;
  if (/^\d+([.,]\d+)?\s*(k|m|s|sec|secs|seconds|reps?)?$/i.test(normalized)) return false;
  if (/^(like|likes|follow|share|save|comment|comments|reel|reels|instagram|tiktok)$/i.test(normalized)) return false;
  if (/^(home|search|collections|profile|import reel|paste link)$/i.test(normalized)) return false;
  if (lowercased.startsWith("http://") || lowercased.startsWith("https://")) return false;

  return true;
}

function normalizeOCRText(text: string): string {
  return dedupeTexts(ocrTextLines(text))
    .join(" ")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

type TranscriptionResult = {
  segments: TranscriptSegment[];
  language: string | null;
};

async function transcribeAudioWithTimestamps(item: Record<string, unknown>): Promise<TranscriptionResult | null> {
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

  const detectedLanguage = typeof transcription.language === "string" ? transcription.language : null;

  const segments = transcription.segments
    .map((rawSegment: unknown) => {
      const segment = objectValue(rawSegment);
      return {
        start: numberValue(segment?.start) ?? 0,
        end: numberValue(segment?.end) ?? 0,
        text: textOrFallback(segment?.text, ""),
      };
    })
    .filter((segment: TranscriptSegment) => segment.text.length > 0 && segment.end > segment.start);

  return { segments, language: detectedLanguage };
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

async function runVideoIntelligenceOCR(videoUrl: string, durationSeconds: number | null, languageHints: string[] = []): Promise<OCREntry[]> {
  if (!googleVideoIntelligenceApiKey) return [];

  const videoResponse = await fetch(videoUrl);
  if (!videoResponse.ok) return [];

  const videoBuffer = await videoResponse.arrayBuffer();
  // Google's inline limit is ~10 MB; stay under to be safe
  if (videoBuffer.byteLength > 9 * 1024 * 1024) {
    console.log(`Video too large for inline Video Intelligence OCR (${videoBuffer.byteLength} bytes), skipping`);
    return [];
  }

  const body: Record<string, unknown> = {
    inputContent: arrayBufferToBase64(videoBuffer),
    features: ["TEXT_DETECTION"],
  };
  if (languageHints.length > 0) {
    body.videoContext = { textDetectionConfig: { languageHints } };
  }

  const submitResponse = await fetch(
    `https://videointelligence.googleapis.com/v1/videos:annotate?key=${googleVideoIntelligenceApiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
  );

  if (!submitResponse.ok) {
    console.warn("Video Intelligence submit failed:", await submitResponse.text());
    return [];
  }

  const operation = await submitResponse.json();
  const operationName = stringValue(operation.name);
  if (!operationName) return [];

  for (let attempt = 0; attempt < 60; attempt++) {
    await delay(2000);
    const pollResponse = await fetch(
      `https://videointelligence.googleapis.com/v1/${operationName}?key=${googleVideoIntelligenceApiKey}`,
    );
    if (!pollResponse.ok) continue;

    const result = await pollResponse.json();
    if (!result.done) continue;
    if (result.error) {
      console.warn("Video Intelligence error:", result.error);
      return [];
    }

    const annotations = result.response?.annotationResults?.[0]?.textAnnotations;
    return Array.isArray(annotations) ? parseVideoIntelligenceText(annotations, durationSeconds) : [];
  }

  console.warn("Video Intelligence polling timed out");
  return [];
}

function parseVideoIntelligenceText(annotations: unknown[], durationSeconds: number | null): OCREntry[] {
  const entries: OCREntry[] = [];
  const duration = durationSeconds ?? 60;

  for (const annotation of annotations) {
    const ann = objectValue(annotation);
    if (!ann) continue;

    const text = stringValue(ann.text);
    if (!text || !isMeaningfulOCRLine(text)) continue;

    const segments = Array.isArray(ann.segments) ? ann.segments : [];
    for (const seg of segments) {
      const s = objectValue(seg);
      if (!s) continue;
      const segmentBounds = objectValue(s.segment);
      const startOffset = stringValue(segmentBounds?.startTimeOffset) ?? "0s";
      const confidence = typeof s.confidence === "number" ? s.confidence : null;
      const ts = Math.min(Math.floor(parseTimeOffset(startOffset)), Math.max(0, duration - 1));
      entries.push({ timestamp_seconds: ts, text, confidence });
    }
  }

  return entries
    .sort((a, b) => a.timestamp_seconds - b.timestamp_seconds)
    .filter((entry, index, arr) =>
      index === 0 ||
      entry.timestamp_seconds !== arr[index - 1].timestamp_seconds ||
      normalizeOCRText(entry.text) !== normalizeOCRText(arr[index - 1].text)
    );
}

function parseTimeOffset(offset: string): number {
  const n = parseFloat(offset.replace("s", ""));
  return Number.isFinite(n) ? n : 0;
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 8192;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
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
