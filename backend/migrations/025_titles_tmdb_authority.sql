-- Migration 025: shared titles TMDB authority (source + refreshed_at).
-- source=client: sync'ten gelen geçici metadata (fill-empty only).
-- source=tmdb: sunucunun TMDB'den yazdığı kanonik satır; client asla ezemez.

ALTER TABLE `titles`
  ADD COLUMN `source` VARCHAR(10) NOT NULL DEFAULT 'client'
    AFTER `metadata_updated_at`,
  ADD COLUMN `refreshed_at` BIGINT NOT NULL DEFAULT 0
    AFTER `source`;

ALTER TABLE `titles`
  ADD KEY `idx_titles_source_refreshed` (`source`, `refreshed_at`);
