-- Arkadaşa film/dizi önerisi (feature: "Arkadaşına Öner")
-- Aynı kişi aynı yapımı aynı arkadaşına tekrar önerirse kayıt güncellenir (uq_rec_once).

CREATE TABLE `recommendations` (
  `id`           bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `from_user_id` bigint(20) UNSIGNED NOT NULL,
  `to_user_id`   bigint(20) UNSIGNED NOT NULL,
  `movie_id`     int(11)        NOT NULL,
  `is_tv`        tinyint(1)     NOT NULL,
  `title`        varchar(512)   NOT NULL,
  `poster_path`  varchar(255)   DEFAULT NULL,
  `note`         varchar(280)   DEFAULT NULL,
  `seen`         tinyint(1)     NOT NULL DEFAULT 0,
  `created_at`   bigint(20)     NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_rec_once` (`from_user_id`, `to_user_id`, `movie_id`, `is_tv`),
  KEY `idx_rec_inbox` (`to_user_id`, `created_at`),
  CONSTRAINT `fk_rec_from` FOREIGN KEY (`from_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_rec_to`   FOREIGN KEY (`to_user_id`)   REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
