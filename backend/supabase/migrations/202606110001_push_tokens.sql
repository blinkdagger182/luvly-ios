-- Push notification device tokens
CREATE TABLE IF NOT EXISTS device_push_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id  UUID NOT NULL REFERENCES reel_social_profiles(id) ON DELETE CASCADE,
  token       TEXT NOT NULL,
  platform    TEXT NOT NULL DEFAULT 'ios',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(profile_id, token)
);

CREATE INDEX IF NOT EXISTS idx_device_push_tokens_profile_id ON device_push_tokens(profile_id);
