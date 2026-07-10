-- Kayıtta e-posta doğrulaması.
-- users.email_verified: 0 = kod bekleniyor (oturum açılamaz), 1 = doğrulanmış.
-- Mevcut kullanıcılar kilitlenmesin diye tümü doğrulanmış işaretlenir;
-- yeni kayıtlar 0 ile açılır ve POST /auth/verify-email ile doğrulanır.

ALTER TABLE `users`
  ADD COLUMN `email_verified` tinyint(1) NOT NULL DEFAULT 0 AFTER `google_sub`;

UPDATE `users` SET `email_verified` = 1;

-- Kayıt doğrulama kodları (password_resets ile aynı desen: bcrypt hash,
-- 15 dk geçerlilik, 3 deneme sınırı).
CREATE TABLE IF NOT EXISTS `email_verifications` (
  `email` varchar(255) NOT NULL,
  `code_hash` varchar(255) NOT NULL,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `expires_at` bigint(20) NOT NULL,
  `created_at` bigint(20) NOT NULL,
  PRIMARY KEY (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
