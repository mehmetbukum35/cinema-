-- Migration 018: isolate localized TMDB metadata by app language.
-- Existing catalog rows have no trustworthy language marker and become `und`.
ALTER TABLE titles
  DROP PRIMARY KEY,
  ADD COLUMN locale VARCHAR(3) NOT NULL DEFAULT 'und' AFTER is_tv,
  ADD PRIMARY KEY (tmdb_id, is_tv, locale);
