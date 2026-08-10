-- Migration 030: which invitation surface produced a signup.
ALTER TABLE users
  ADD COLUMN signup_source VARCHAR(32) NULL AFTER email_verified;
