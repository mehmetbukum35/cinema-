-- Sunucu-otoriter senkron imleci.
--
-- Sorun: pull `since` imleci SUNUCU saatiyle (server_time) ilerliyordu ama
-- satırlar CİHAZ saatli `updated_at` ile filtreleniyordu. Saati geride bir
-- cihazın yazdıkları, başka cihazların cursor'unun altında kalıp kalıcı olarak
-- atlanıyordu (çok-cihazlı veri kaybı).
--
-- Çözüm: her sync tablosuna, her yazımda sunucu saatiyle damgalanan
-- `server_updated_at` kolonu. Pull artık bunu filtreler; çakışma çözümü (hangi
-- satır kazanır) yine client `updated_at`'iyle yapılır.
--
-- Not: MariaDB (cPanel) `IF NOT EXISTS` destekler; manuel çalıştırmada güvenli
-- tekrar için kullanıldı. Saf MySQL'de `IF NOT EXISTS` desteklenmezse ilgili
-- ibareyi kaldırıp bir kez çalıştırın.

ALTER TABLE `ratings`         ADD COLUMN IF NOT EXISTS `server_updated_at` bigint(20) NOT NULL DEFAULT 0;
UPDATE `ratings`         SET `server_updated_at` = `updated_at` WHERE `server_updated_at` = 0;
ALTER TABLE `ratings`         ADD INDEX IF NOT EXISTS `idx_ratings_server_sync` (`user_id`,`server_updated_at`);

ALTER TABLE `watchlist`       ADD COLUMN IF NOT EXISTS `server_updated_at` bigint(20) NOT NULL DEFAULT 0;
UPDATE `watchlist`       SET `server_updated_at` = `updated_at` WHERE `server_updated_at` = 0;
ALTER TABLE `watchlist`       ADD INDEX IF NOT EXISTS `idx_watchlist_server_sync` (`user_id`,`server_updated_at`);

ALTER TABLE `favorites`       ADD COLUMN IF NOT EXISTS `server_updated_at` bigint(20) NOT NULL DEFAULT 0;
UPDATE `favorites`       SET `server_updated_at` = `updated_at` WHERE `server_updated_at` = 0;
ALTER TABLE `favorites`       ADD INDEX IF NOT EXISTS `idx_favorites_server_sync` (`user_id`,`server_updated_at`);

ALTER TABLE `watched_seasons` ADD COLUMN IF NOT EXISTS `server_updated_at` bigint(20) NOT NULL DEFAULT 0;
UPDATE `watched_seasons` SET `server_updated_at` = `updated_at` WHERE `server_updated_at` = 0;
ALTER TABLE `watched_seasons` ADD INDEX IF NOT EXISTS `idx_ws_server_sync` (`user_id`,`server_updated_at`);

ALTER TABLE `search_history`  ADD COLUMN IF NOT EXISTS `server_updated_at` bigint(20) NOT NULL DEFAULT 0;
UPDATE `search_history`  SET `server_updated_at` = `updated_at` WHERE `server_updated_at` = 0;
ALTER TABLE `search_history`  ADD INDEX IF NOT EXISTS `idx_sh_server_sync` (`user_id`,`server_updated_at`);
