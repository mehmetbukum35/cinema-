-- Migration 005: Add rate_limits table for DB-based rate limiting
CREATE TABLE IF NOT EXISTS `rate_limits` (
  `ip_bucket` VARCHAR(100) NOT NULL,
  `window_time` INT NOT NULL,
  `request_count` INT NOT NULL DEFAULT 1,
  PRIMARY KEY (`ip_bucket`, `window_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
