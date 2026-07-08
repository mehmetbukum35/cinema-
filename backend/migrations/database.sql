-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Anamakine: localhost:3306
-- Üretim Zamanı: 29 Haz 2026, 15:17:56
-- Sunucu sürümü: 10.6.25-MariaDB-cll-lve-log
-- PHP Sürümü: 8.4.21

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Veritabanı: `foodlabe_cinema`
--

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `favorites`
--

CREATE TABLE `favorites` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `id` int(11) NOT NULL,
  `is_tv` tinyint(1) NOT NULL,
  `title` varchar(512) NOT NULL,
  `poster_path` varchar(255) DEFAULT NULL,
  `backdrop_path` varchar(255) DEFAULT NULL,
  `overview` text DEFAULT NULL,
  `vote_average` double DEFAULT NULL,
  `release_date` varchar(20) DEFAULT NULL,
  `genre_ids` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`genre_ids`)),
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `deleted` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `friends`
--

CREATE TABLE `friends` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `friend_id` bigint(20) UNSIGNED NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'pending',
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `password_resets`
--

CREATE TABLE `password_resets` (
  `email` varchar(255) NOT NULL,
  `code_hash` varchar(255) NOT NULL,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `expires_at` bigint(20) NOT NULL,
  `created_at` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `ratings`
--

CREATE TABLE `ratings` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `movie_id` int(11) NOT NULL,
  `is_tv` tinyint(1) NOT NULL,
  `rating` int(11) NOT NULL,
  `genre_ids` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`genre_ids`)),
  `title` varchar(512) DEFAULT NULL,
  `poster_path` varchar(255) DEFAULT NULL,
  `backdrop_path` varchar(255) DEFAULT NULL,
  `overview` text DEFAULT NULL,
  `vote_average` double DEFAULT NULL,
  `release_date` varchar(20) DEFAULT NULL,
  `popularity` double DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `is_spoiler` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `deleted` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `recommendations`
--

CREATE TABLE `recommendations` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `from_user_id` bigint(20) UNSIGNED NOT NULL,
  `to_user_id` bigint(20) UNSIGNED NOT NULL,
  `movie_id` int(11) NOT NULL,
  `is_tv` tinyint(1) NOT NULL,
  `title` varchar(512) NOT NULL,
  `poster_path` varchar(255) DEFAULT NULL,
  `note` varchar(280) DEFAULT NULL,
  `seen` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `refresh_tokens`
--

CREATE TABLE `refresh_tokens` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `token_hash` char(64) NOT NULL,
  `expires_at` bigint(20) NOT NULL,
  `created_at` bigint(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `search_history`
--

CREATE TABLE `search_history` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `query` varchar(255) NOT NULL,
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `deleted` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `users`
--

CREATE TABLE `users` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `email` varchar(255) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `display_name` varchar(100) DEFAULT NULL,
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `username` varchar(50) DEFAULT NULL,
  `is_public` tinyint(1) NOT NULL DEFAULT 1,
  `taste_dna` text DEFAULT NULL,
  `taste_dna_at` bigint(20) NOT NULL DEFAULT 0,
  `google_sub` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `watched_seasons`
--

CREATE TABLE `watched_seasons` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `tv_id` int(11) NOT NULL,
  `season_number` int(11) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `deleted` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo için tablo yapısı `watchlist`
--

CREATE TABLE `watchlist` (
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `id` int(11) NOT NULL,
  `is_tv` tinyint(1) NOT NULL,
  `title` varchar(512) NOT NULL,
  `poster_path` varchar(255) DEFAULT NULL,
  `backdrop_path` varchar(255) DEFAULT NULL,
  `overview` text DEFAULT NULL,
  `vote_average` double DEFAULT NULL,
  `release_date` varchar(20) DEFAULT NULL,
  `genre_ids` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`genre_ids`)),
  `created_at` bigint(20) NOT NULL,
  `updated_at` bigint(20) NOT NULL,
  `deleted` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dökümü yapılmış tablolar için indeksler
--

--
-- Tablo için indeksler `favorites`
--
ALTER TABLE `favorites`
  ADD PRIMARY KEY (`user_id`,`id`,`is_tv`),
  ADD KEY `idx_favorites_sync` (`user_id`,`updated_at`);

--
-- Tablo için indeksler `friends`
--
ALTER TABLE `friends`
  ADD PRIMARY KEY (`user_id`,`friend_id`),
  ADD KEY `fk_friends_friend` (`friend_id`);

--
-- Tablo için indeksler `password_resets`
--
ALTER TABLE `password_resets`
  ADD PRIMARY KEY (`email`);

--
-- Tablo için indeksler `ratings`
--
ALTER TABLE `ratings`
  ADD PRIMARY KEY (`user_id`,`movie_id`,`is_tv`),
  ADD KEY `idx_ratings_sync` (`user_id`,`updated_at`);

--
-- Tablo için indeksler `recommendations`
--
ALTER TABLE `recommendations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_rec_once` (`from_user_id`,`to_user_id`,`movie_id`,`is_tv`),
  ADD KEY `idx_rec_inbox` (`to_user_id`,`created_at`);

--
-- Tablo için indeksler `refresh_tokens`
--
ALTER TABLE `refresh_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_rt_hash` (`token_hash`),
  ADD KEY `idx_rt_user` (`user_id`);

--
-- Tablo için indeksler `search_history`
--
ALTER TABLE `search_history`
  ADD PRIMARY KEY (`user_id`,`query`),
  ADD KEY `idx_sh_sync` (`user_id`,`updated_at`);

--
-- Tablo için indeksler `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_users_email` (`email`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `idx_users_google_sub` (`google_sub`);

--
-- Tablo için indeksler `watched_seasons`
--
ALTER TABLE `watched_seasons`
  ADD PRIMARY KEY (`user_id`,`tv_id`,`season_number`),
  ADD KEY `idx_ws_sync` (`user_id`,`updated_at`);

--
-- Tablo için indeksler `watchlist`
--
ALTER TABLE `watchlist`
  ADD PRIMARY KEY (`user_id`,`id`,`is_tv`),
  ADD KEY `idx_watchlist_sync` (`user_id`,`updated_at`);

--
-- Dökümü yapılmış tablolar için AUTO_INCREMENT değeri
--

--
-- Tablo için AUTO_INCREMENT değeri `recommendations`
--
ALTER TABLE `recommendations`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `refresh_tokens`
--
ALTER TABLE `refresh_tokens`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Tablo için AUTO_INCREMENT değeri `users`
--
ALTER TABLE `users`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Dökümü yapılmış tablolar için kısıtlamalar
--

--
-- Tablo kısıtlamaları `favorites`
--
ALTER TABLE `favorites`
  ADD CONSTRAINT `fk_favorites_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `friends`
--
ALTER TABLE `friends`
  ADD CONSTRAINT `fk_friends_friend` FOREIGN KEY (`friend_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_friends_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `ratings`
--
ALTER TABLE `ratings`
  ADD CONSTRAINT `fk_ratings_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `recommendations`
--
ALTER TABLE `recommendations`
  ADD CONSTRAINT `fk_rec_from` FOREIGN KEY (`from_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_rec_to` FOREIGN KEY (`to_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `refresh_tokens`
--
ALTER TABLE `refresh_tokens`
  ADD CONSTRAINT `fk_rt_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `search_history`
--
ALTER TABLE `search_history`
  ADD CONSTRAINT `fk_sh_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `watched_seasons`
--
ALTER TABLE `watched_seasons`
  ADD CONSTRAINT `fk_ws_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Tablo kısıtlamaları `watchlist`
--
ALTER TABLE `watchlist`
  ADD CONSTRAINT `fk_watchlist_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

-- --------------------------------------------------------

--
-- Tablo yapısı: `device_tokens` (FCM push bildirimleri)
--
CREATE TABLE `device_tokens` (
  `token`      varchar(255)    NOT NULL,
  `user_id`    bigint(20) UNSIGNED NOT NULL,
  `platform`   varchar(20)     DEFAULT NULL,
  `created_at` bigint(20)      NOT NULL,
  `updated_at` bigint(20)      NOT NULL,
  PRIMARY KEY (`token`),
  KEY `idx_device_tokens_user` (`user_id`),
  CONSTRAINT `fk_device_tokens_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Tablo yapısı: `rate_limits` (DB rate limiting)
--
CREATE TABLE IF NOT EXISTS `rate_limits` (
  `ip_bucket` varchar(100) NOT NULL,
  `window_time` int(11) NOT NULL,
  `request_count` int(11) NOT NULL DEFAULT 1,
  PRIMARY KEY (`ip_bucket`,`window_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
