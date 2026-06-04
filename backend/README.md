# LockInNote Reels Backend

This backend imports Instagram/TikTok reel URLs through Apify, summarizes them with OpenAI, and stores reels plus timestamped segments in Supabase.

Apify transcript billing is intentionally disabled. The reel Actor input uses `includeTranscript: false` so imports do not trigger the paid transcript add-on. When timestamped text is needed, the Edge Function transcribes from the media URL with OpenAI instead.

## Local config

Secrets live in `backend/.env`.

Deploying also needs a Supabase management token:

```sh
SUPABASE_ACCESS_TOKEN=sbp_...
```

The iOS app only needs the Supabase URL and anon key. Regenerate the client-safe Swift config after editing `.env`:

```sh
./backend/scripts/generate-ios-reel-config.sh
```

## Deploy

Install or authenticate the Supabase CLI first, then run:

```sh
cd LockInNote
./backend/scripts/deploy-reels-backend.sh
```

The script derives the project ref from `NEXT_PUBLIC_SUPABASE_URL`, pushes the migration, sets Edge Function secrets, and deploys the `reels` function.
