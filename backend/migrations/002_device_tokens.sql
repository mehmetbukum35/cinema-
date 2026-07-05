-- Migration 002: FCM push bildirimleri için cihaz token tablosu.
-- Mevcut bir kuruluma eklemek için bu dosyayı çalıştır (database.sql'e de dahildir).

CREATE TABLE IF NOT EXISTS `device_tokens` (
  `token`      varchar(255)        NOT NULL,
  `user_id`    bigint(20) UNSIGNED NOT NULL,
  `platform`   varchar(20)         DEFAULT NULL,   -- 'android' | 'ios' | 'web'
  `created_at` bigint(20)          NOT NULL,
  `updated_at` bigint(20)          NOT NULL,
  PRIMARY KEY (`token`),                            -- token tekildir
  KEY `idx_device_tokens_user` (`user_id`),         -- kullanıcının cihazlarını çekmek için
  CONSTRAINT `fk_device_tokens_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
