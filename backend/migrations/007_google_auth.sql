-- Migration 007: Google Sign-In hesap bağlama.
-- google_sub: Google'ın değişmez kullanıcı kimliği (ID token 'sub' claim'i).
-- E-posta değişse bile hesap eşleşmesi bozulmaz. NULL = Google bağlanmamış.
ALTER TABLE users ADD COLUMN google_sub VARCHAR(64) NULL;
CREATE UNIQUE INDEX idx_users_google_sub ON users (google_sub);
