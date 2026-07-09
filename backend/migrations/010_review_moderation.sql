-- Migration 010: Yorum moderasyonu altyapısı.
-- is_hidden: sunucu tarafı gizleme bayrağı (sync ile istemciye AKTARILMAZ);
-- kullanıcının verisi bozulmadan yorum başkalarından gizlenir.
ALTER TABLE ratings ADD COLUMN is_hidden TINYINT(1) NOT NULL DEFAULT 0;

-- Başlık bazlı yorum/skor sorguları (getTitleReviews, getTitleScore) için indeks;
-- şimdiye kadar yalnızca (user_id, ...) indeksleri vardı, movie bazlı sorgular tam taramaydı.
ALTER TABLE ratings ADD KEY idx_ratings_title (movie_id, is_tv);

-- Yorum şikayetleri: aynı kullanıcı aynı yorumu bir kez şikayet edebilir (PK).
-- status: open → moderatör aksiyonuyla resolved/dismissed.
CREATE TABLE review_reports (
  reporter_id      BIGINT(20) UNSIGNED NOT NULL,
  reported_user_id BIGINT(20) UNSIGNED NOT NULL,
  movie_id         INT(11) NOT NULL,
  is_tv            TINYINT(1) NOT NULL,
  reason           VARCHAR(40) NOT NULL DEFAULT 'other',
  status           VARCHAR(20) NOT NULL DEFAULT 'open',
  created_at       BIGINT(20) NOT NULL,
  PRIMARY KEY (reporter_id, reported_user_id, movie_id, is_tv),
  KEY idx_reports_review (reported_user_id, movie_id, is_tv),
  KEY idx_reports_status (status, created_at),
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_reported FOREIGN KEY (reported_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Kullanıcı engelleme: engelleyen, engellenenin yorumlarını/aktivitesini görmez.
CREATE TABLE user_blocks (
  user_id         BIGINT(20) UNSIGNED NOT NULL,
  blocked_user_id BIGINT(20) UNSIGNED NOT NULL,
  created_at      BIGINT(20) NOT NULL,
  PRIMARY KEY (user_id, blocked_user_id),
  KEY idx_blocks_blocked (blocked_user_id),
  CONSTRAINT fk_blocks_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_blocks_blocked FOREIGN KEY (blocked_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
