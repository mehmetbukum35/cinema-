-- Migration 013: Sign in with Apple hesap bağlama.
-- apple_sub: Apple'ın değişmez kullanıcı kimliği (identity token 'sub' claim'i).
-- E-posta değişse/gizlense bile hesap eşleşmesi bozulmaz. NULL = Apple bağlanmamış.
ALTER TABLE users ADD COLUMN apple_sub VARCHAR(64) NULL;
CREATE UNIQUE INDEX idx_users_apple_sub ON users (apple_sub);
