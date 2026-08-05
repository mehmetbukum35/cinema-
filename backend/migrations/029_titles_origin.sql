-- Migration 029: culture metadata on shared titles catalog.
ALTER TABLE titles
  ADD COLUMN original_language VARCHAR(16) NULL AFTER genre_ids,
  ADD COLUMN origin_countries LONGTEXT
    CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL AFTER original_language;
