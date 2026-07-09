-- Migration 011: Yorum yasağı (susturma). Moderasyon panelinden verilen bu
-- bayrak, kullanıcının MEVCUT ve GELECEKTEKİ tüm yorumlarını başkalarından
-- gizler (sync upsert'i yeni yorumları otomatik is_hidden=1 yazar). Hesap
-- silinmez, puanlama çalışmaya devam eder — yalnızca yorum görünürlüğü kısıtlanır.
ALTER TABLE users ADD COLUMN review_banned TINYINT(1) NOT NULL DEFAULT 0;
