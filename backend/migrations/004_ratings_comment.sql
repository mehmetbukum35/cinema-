-- Migration 004: Add comment and is_spoiler columns to ratings table
ALTER TABLE ratings ADD COLUMN comment TEXT NULL;
ALTER TABLE ratings ADD COLUMN is_spoiler TINYINT NOT NULL DEFAULT 0;
