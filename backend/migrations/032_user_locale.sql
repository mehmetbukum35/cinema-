ALTER TABLE `users`
  ADD COLUMN `locale` VARCHAR(5) NOT NULL DEFAULT 'tr' AFTER `review_banned`;
