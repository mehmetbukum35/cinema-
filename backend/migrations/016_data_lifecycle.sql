-- Migration 016: bounded data lifecycle and cleanup indexes.
-- Couch voting performs concurrent writes; InnoDB avoids MyISAM table locks.
ALTER TABLE couch_sessions ENGINE=InnoDB;

CREATE INDEX idx_couch_lifecycle ON couch_sessions (status, updated_at);
CREATE INDEX idx_ratings_tombstone ON ratings (deleted, updated_at);
CREATE INDEX idx_search_history_retention ON search_history (user_id, deleted, updated_at);
CREATE INDEX idx_refresh_tokens_expiry ON refresh_tokens (expires_at);
CREATE INDEX idx_password_resets_expiry ON password_resets (expires_at);
CREATE INDEX idx_email_verifications_expiry ON email_verifications (expires_at);
