-- Migration 009: Profil beğenileri ("Popüler Listeler" sıralaması).
-- Bir üye, başka bir üyenin herkese açık profilini/listelerini beğenebilir.
-- PK (voter_id, owner_id): kullanıcı başına tek beğeni; geri alınca satır silinir.
CREATE TABLE IF NOT EXISTS `profile_likes` (
  `voter_id` BIGINT(20) UNSIGNED NOT NULL,
  `owner_id` BIGINT(20) UNSIGNED NOT NULL,
  `created_at` BIGINT(20) NOT NULL,
  PRIMARY KEY (`voter_id`, `owner_id`),
  KEY `idx_profile_likes_owner` (`owner_id`),
  CONSTRAINT `fk_profile_likes_voter` FOREIGN KEY (`voter_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_profile_likes_owner` FOREIGN KEY (`owner_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
