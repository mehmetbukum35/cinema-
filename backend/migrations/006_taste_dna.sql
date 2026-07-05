-- Migration 006: Sinema DNA snapshot'ı (public web kartında render edilir).
-- Algoritma cihazda (Dart TasteDnaService) çalışır; sunucu yalnızca kullanıcının
-- yayınladığı hazır snapshot'ı saklar (tek doğruluk kaynağı = Dart motoru).
ALTER TABLE users ADD COLUMN taste_dna TEXT NULL;
ALTER TABLE users ADD COLUMN taste_dna_at BIGINT NOT NULL DEFAULT 0;
