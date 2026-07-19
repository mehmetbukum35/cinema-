-- Migration 017: normalize shared TMDB metadata into one canonical catalog.
CREATE TABLE titles (
  tmdb_id INT NOT NULL,
  is_tv TINYINT(1) NOT NULL,
  title VARCHAR(512) NULL,
  poster_path VARCHAR(255) NULL,
  backdrop_path VARCHAR(255) NULL,
  overview TEXT NULL,
  vote_average DOUBLE NULL,
  release_date VARCHAR(20) NULL,
  popularity DOUBLE NULL,
  genre_ids LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL,
  metadata_updated_at BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (tmdb_id, is_tv),
  KEY idx_titles_metadata_updated (metadata_updated_at),
  CONSTRAINT chk_titles_genres CHECK (genre_ids IS NULL OR JSON_VALID(genre_ids))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- During the two-step rollout the new backend stops writing legacy metadata.
-- Make the only required legacy fields nullable before that code is deployed.
ALTER TABLE watchlist MODIFY COLUMN title VARCHAR(512) NULL;
ALTER TABLE favorites MODIFY COLUMN title VARCHAR(512) NULL;

-- Backfill all active sources. Later sources fill missing fields without
-- replacing an existing non-empty value with an empty one.
INSERT INTO titles
  (tmdb_id, is_tv, title, poster_path, backdrop_path, overview, vote_average,
   release_date, popularity, genre_ids, metadata_updated_at)
SELECT r.movie_id, r.is_tv, NULLIF(r.title, ''), r.poster_path, r.backdrop_path, r.overview,
       r.vote_average, r.release_date, r.popularity, r.genre_ids, r.updated_at
FROM ratings r WHERE r.deleted = 0
ON DUPLICATE KEY UPDATE
  title = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(title), ''), titles.title), titles.title),
  poster_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(poster_path), titles.poster_path), titles.poster_path),
  backdrop_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(backdrop_path), titles.backdrop_path), titles.backdrop_path),
  overview = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(overview), ''), titles.overview), titles.overview),
  vote_average = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(vote_average), titles.vote_average), titles.vote_average),
  release_date = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(release_date), ''), titles.release_date), titles.release_date),
  popularity = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(popularity), titles.popularity), titles.popularity),
  genre_ids = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(genre_ids), titles.genre_ids), titles.genre_ids),
  metadata_updated_at = GREATEST(titles.metadata_updated_at, VALUES(metadata_updated_at));

INSERT INTO titles
  (tmdb_id, is_tv, title, poster_path, backdrop_path, overview, vote_average,
   release_date, genre_ids, metadata_updated_at)
SELECT w.id, w.is_tv, NULLIF(w.title, ''), w.poster_path, w.backdrop_path, w.overview,
       w.vote_average, w.release_date, w.genre_ids, w.updated_at
FROM watchlist w WHERE w.deleted = 0
ON DUPLICATE KEY UPDATE
  title = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(title), ''), titles.title), titles.title),
  poster_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(poster_path), titles.poster_path), titles.poster_path),
  backdrop_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(backdrop_path), titles.backdrop_path), titles.backdrop_path),
  overview = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(overview), ''), titles.overview), titles.overview),
  vote_average = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(vote_average), titles.vote_average), titles.vote_average),
  release_date = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(release_date), ''), titles.release_date), titles.release_date),
  genre_ids = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(genre_ids), titles.genre_ids), titles.genre_ids),
  metadata_updated_at = GREATEST(titles.metadata_updated_at, VALUES(metadata_updated_at));

INSERT INTO titles
  (tmdb_id, is_tv, title, poster_path, backdrop_path, overview, vote_average,
   release_date, genre_ids, metadata_updated_at)
SELECT f.id, f.is_tv, NULLIF(f.title, ''), f.poster_path, f.backdrop_path, f.overview,
       f.vote_average, f.release_date, f.genre_ids, f.updated_at
FROM favorites f WHERE f.deleted = 0
ON DUPLICATE KEY UPDATE
  title = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(title), ''), titles.title), titles.title),
  poster_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(poster_path), titles.poster_path), titles.poster_path),
  backdrop_path = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(backdrop_path), titles.backdrop_path), titles.backdrop_path),
  overview = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(overview), ''), titles.overview), titles.overview),
  vote_average = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(vote_average), titles.vote_average), titles.vote_average),
  release_date = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(NULLIF(VALUES(release_date), ''), titles.release_date), titles.release_date),
  genre_ids = IF(VALUES(metadata_updated_at) >= titles.metadata_updated_at, COALESCE(VALUES(genre_ids), titles.genre_ids), titles.genre_ids),
  metadata_updated_at = GREATEST(titles.metadata_updated_at, VALUES(metadata_updated_at));

-- Legacy metadata columns are intentionally kept during this migration.
-- Deploy the catalog-aware backend, verify it, then run migration 018.
