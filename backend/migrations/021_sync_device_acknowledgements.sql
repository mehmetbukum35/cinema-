-- Device-aware tombstone garbage collection.
-- Run once after deploying backend support, before enabling maintenance GC.

CREATE TABLE IF NOT EXISTS `sync_devices` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `device_id` varchar(64) NOT NULL,
  `last_ack_cursor` bigint(20) NOT NULL DEFAULT 0,
  `last_seen_at` bigint(20) NOT NULL,
  `created_at` bigint(20) NOT NULL,
  `invalidated_at` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`user_id`, `device_id`),
  KEY `idx_sync_devices_gc` (`user_id`, `invalidated_at`, `last_ack_cursor`),
  KEY `idx_sync_devices_last_seen` (`last_seen_at`),
  CONSTRAINT `fk_sync_devices_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `sync_gc_state` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `gc_cursor` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` bigint(20) NOT NULL,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_sync_gc_state_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE INDEX `idx_watchlist_tombstone_gc` ON `watchlist` (`deleted`, `updated_at`, `user_id`);
CREATE INDEX `idx_favorites_tombstone_gc` ON `favorites` (`deleted`, `updated_at`, `user_id`);
CREATE INDEX `idx_watched_seasons_tombstone_gc` ON `watched_seasons` (`deleted`, `updated_at`, `user_id`);
CREATE INDEX `idx_search_history_tombstone_gc` ON `search_history` (`deleted`, `updated_at`, `user_id`);
