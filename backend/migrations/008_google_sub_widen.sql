-- Migration 008: google_sub sütununu genişlet.
-- OIDC "sub" claim'i spesifikasyona göre 255 karaktere kadar olabilir; Google
-- şu an ~21 hane döndürse de ileriye dönük 64 → 255 genişletilir. UNIQUE index
-- (idx_users_google_sub) korunur.
ALTER TABLE users MODIFY google_sub VARCHAR(255) NULL;
