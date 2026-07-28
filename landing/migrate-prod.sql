-- Migration for the EXISTING prod D1 (already has pets + uploads).
-- Adds owner/counters to pets and the new portal tables. Run once:
--   wrangler d1 execute desktoppet-pets --remote --file=landing/migrate-prod.sql
ALTER TABLE pets ADD COLUMN user_id INTEGER;
ALTER TABLE pets ADD COLUMN downloads INTEGER NOT NULL DEFAULT 0;
ALTER TABLE pets ADD COLUMN likes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE pets ADD COLUMN description TEXT;
CREATE INDEX IF NOT EXISTS idx_pets_user ON pets(user_id);

CREATE TABLE IF NOT EXISTS users (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  provider    TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  name        TEXT NOT NULL,
  avatar_url  TEXT,
  created_at  INTEGER NOT NULL,
  UNIQUE(provider, provider_id)
);
CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,
  user_id     INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE TABLE IF NOT EXISTS pet_likes (
  pet_slug    TEXT NOT NULL,
  user_id     INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (pet_slug, user_id)
);
CREATE TABLE IF NOT EXISTS downloads_log (
  ip          TEXT NOT NULL,
  pet_slug    TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dl_ip_slug_time ON downloads_log(ip, pet_slug, created_at);
