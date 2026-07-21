-- Migration 022: precomputed community "Popüler Top 20" charts.
--
-- Populated by Maintenance::recomputePopularTitles() on the cron schedule and
-- served read-only by GET /titles/popular. The heavy GROUP BY over `favorites`
-- runs in the cron (off the request path); the endpoint only reads these 20
-- rows per type. Locale-agnostic on purpose — poster/title metadata is joined
-- from `titles` at request time so one precompute serves every locale.
CREATE TABLE IF NOT EXISTS `popular_titles` (
  `is_tv` tinyint(1) NOT NULL,
  `rank` smallint(6) NOT NULL,
  `tmdb_id` int(11) NOT NULL,
  `votes` int(11) NOT NULL,
  `computed_at` bigint(20) NOT NULL,
  PRIMARY KEY (`is_tv`, `rank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Aggregation support: COUNT(DISTINCT user_id) GROUP BY id over active
-- favorites, filtered by type. Existing favorites indexes are user_id-first.
CREATE INDEX `idx_favorites_popular` ON `favorites` (`is_tv`, `deleted`, `id`);
