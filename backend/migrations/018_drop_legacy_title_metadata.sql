-- Migration 018: remove metadata duplicated in user relation tables.
-- Run only after the catalog-aware backend has been deployed and verified.
ALTER TABLE ratings
  DROP COLUMN genre_ids,
  DROP COLUMN title,
  DROP COLUMN poster_path,
  DROP COLUMN backdrop_path,
  DROP COLUMN overview,
  DROP COLUMN vote_average,
  DROP COLUMN release_date,
  DROP COLUMN popularity;

ALTER TABLE watchlist
  DROP COLUMN title,
  DROP COLUMN poster_path,
  DROP COLUMN backdrop_path,
  DROP COLUMN overview,
  DROP COLUMN vote_average,
  DROP COLUMN release_date,
  DROP COLUMN genre_ids;

ALTER TABLE favorites
  DROP COLUMN title,
  DROP COLUMN poster_path,
  DROP COLUMN backdrop_path,
  DROP COLUMN overview,
  DROP COLUMN vote_average,
  DROP COLUMN release_date,
  DROP COLUMN genre_ids;
