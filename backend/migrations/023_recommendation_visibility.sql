-- Gönderen ve alıcı öneri geçmişlerini birbirinden bağımsız temizleyebilsin.
ALTER TABLE `recommendations`
  ADD COLUMN `sender_deleted` tinyint(1) NOT NULL DEFAULT 0 AFTER `seen`,
  ADD COLUMN `recipient_deleted` tinyint(1) NOT NULL DEFAULT 0 AFTER `sender_deleted`;
