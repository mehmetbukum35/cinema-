ALTER TABLE users
  ADD COLUMN cultural_preferences TEXT NULL AFTER taste_dna_at,
  ADD COLUMN cultural_preferences_updated_at BIGINT NOT NULL DEFAULT 0
    AFTER cultural_preferences;
