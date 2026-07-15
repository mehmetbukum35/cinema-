-- Migration 014: "Birlikte Seç" (canlı kanepe modu) oturumları.
-- İki arkadaş kendi telefonlarından AYNI desteyi kaydırır; ikisinin de
-- beğendiği ilk yapımda oturum 'matched' olur. Deste ve oylar JSON kolonlarda
-- tutulur: paylaşımlı hosting'de ek tablo/join maliyeti yerine oturum başına
-- tek satır. Oylar kullanıcı başına AYRI kolonda (host_votes/guest_votes) —
-- iki taraf eşzamanlı yazsa bile birbirinin verisini ezemez.
-- status: pending (misafir henüz katılmadı) | active | matched | ended | cancelled
CREATE TABLE couch_sessions (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  host_id INT UNSIGNED NOT NULL,
  guest_id INT UNSIGNED NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  deck MEDIUMTEXT NOT NULL,
  host_votes TEXT NOT NULL,
  guest_votes TEXT NOT NULL,
  matched_key VARCHAR(32) NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  CONSTRAINT fk_couch_host FOREIGN KEY (host_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_couch_guest FOREIGN KEY (guest_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE INDEX idx_couch_host_status ON couch_sessions (host_id, status);
CREATE INDEX idx_couch_guest_status ON couch_sessions (guest_id, status);
