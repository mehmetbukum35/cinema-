<?php
declare(strict_types=1);
// Kimlik doğrulama: register / login / refresh / logout / me / change-password / delete-account
require_once __DIR__ . '/Jwt.php';

class Auth
{
    public function __construct(private PDO $db, private array $cfg) {}

    // ─── Korumalı uçlar için: Bearer access token'ı doğrula, user_id döndür ──
    public function requireUser(): int
    {
        $token = bearer_token();
        if (!$token) fail(401, 'Yetkilendirme başlığı yok.');
        $payload = Jwt::decode($token, $this->cfg['jwt_secret']);
        if (!$payload || ($payload['typ'] ?? '') !== 'access') {
            fail(401, 'Geçersiz veya süresi dolmuş oturum.');
        }
        return (int) $payload['sub'];
    }

    // ─── POST /auth/register ────────────────────────────────────────────────
    public function register(array $in): void
    {
        $email = strtolower(trim($in['email'] ?? ''));
        $pass  = (string) ($in['password'] ?? '');
        $name  = isset($in['display_name']) ? trim($in['display_name']) : null;

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) fail(422, 'Geçersiz e-posta.');
        if (strlen($pass) < 8) fail(422, 'Parola en az 8 karakter olmalı.');

        $exists = $this->db->prepare('SELECT 1 FROM users WHERE email = ?');
        $exists->execute([$email]);
        if ($exists->fetch()) fail(409, 'Bu e-posta zaten kayıtlı.');

        $t = now_ms();
        $hash = password_hash($pass, PASSWORD_BCRYPT);
        $ins = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)'
        );
        $ins->execute([$email, $hash, $name, $t, $t]);
        $uid = (int) $this->db->lastInsertId();

        json_out(201, [
            'user'   => ['id' => $uid, 'email' => $email, 'display_name' => $name],
            'tokens' => $this->issueTokens($uid),
        ]);
    }

    // ─── POST /auth/login ───────────────────────────────────────────────────
    public function login(array $in): void
    {
        $email = strtolower(trim($in['email'] ?? ''));
        $pass  = (string) ($in['password'] ?? '');

        $st = $this->db->prepare('SELECT id, password_hash, display_name, username FROM users WHERE email = ?');
        $st->execute([$email]);
        $u = $st->fetch();

        if (!$u) {
            // Zamanlama farkıyla e-posta varlığı sızmasın diye kullanıcı yokken
            // de bcrypt maliyeti ödenir (sahte hash ile doğrulama).
            password_verify($pass, '$2y$10$abcdefghijklmnopqrstuv0123456789012345678901234567890');
            fail(401, 'E-posta veya parola hatalı.');
        }
        if (!password_verify($pass, $u['password_hash'])) {
            fail(401, 'E-posta veya parola hatalı.');
        }
        $uid = (int) $u['id'];
        json_out(200, [
            'user'   => [
                'id' => $uid,
                'email' => $email,
                'display_name' => $u['display_name'],
                'username' => $u['username']
            ],
            'tokens' => $this->issueTokens($uid),
        ]);
    }

    // ─── POST /auth/google ──────────────────────────────────────────────────
    // Google Sign-In: istemcinin gönderdiği ID token doğrulanır, kullanıcı
    // google_sub ile bulunur; yoksa AYNI e-postalı hesaba bağlanır (Google
    // e-postayı doğruladığı için güvenli); o da yoksa yeni hesap açılır.
    // Oturum yine bizim JWT/refresh boru hattımızla yönetilir.
    // $verifier: testler için enjekte edilebilir (idToken → claims|null).
    public function googleLogin(array $in, ?callable $verifier = null): void
    {
        $idToken = (string) ($in['id_token'] ?? '');
        if ($idToken === '') {
            fail(422, 'id_token gerekli.');
        }

        $clientIds = (array) ($this->cfg['google']['client_ids'] ?? []);
        if ($clientIds === []) {
            fail(500, 'Google girişi sunucuda yapılandırılmamış (google.client_ids eksik).');
        }

        $verifier ??= fn (string $t) => GoogleAuth::verifyIdToken($t, $clientIds);
        $claims = $verifier($idToken);
        if ($claims === null) {
            fail(401, 'Google kimliği doğrulanamadı.');
        }

        $sub = (string) $claims['sub'];
        $email = strtolower(trim((string) $claims['email']));
        $name = isset($claims['name']) ? trim((string) $claims['name']) : null;

        // Hesabı bul/bağla/oluştur. Eşzamanlı ilk girişlerde UNIQUE ihlali
        // (google_sub / email) doğabileceğinden transaction + tek retry ile sarılır.
        [$uid, $email, $name, $username, $isNew] =
            $this->resolveGoogleAccount($sub, $email, $name);

        json_out(200, [
            'user' => [
                'id' => $uid,
                'email' => $email,
                'display_name' => $name,
                'username' => $username,
            ],
            'tokens' => $this->issueTokens($uid),
            'is_new' => $isNew,
        ]);
    }

    /**
     * Google hesabını bul/bağla/oluştur; [uid, email, name, username, isNew] döner.
     * Transaction içinde çalışır; eşzamanlı iki istek aynı yeni kullanıcıyı
     * yaratmaya çalışırsa oluşan UNIQUE ihlali yakalanıp bir kez yeniden denenir
     * (ikinci turda kayıt artık mevcut olduğundan SELECT ile bulunur).
     */
    private function resolveGoogleAccount(string $sub, string $email, ?string $name): array
    {
        for ($attempt = 0; $attempt < 2; $attempt++) {
            try {
                $this->db->beginTransaction();
                $result = $this->findOrCreateGoogleUser($sub, $email, $name);
                $this->db->commit();
                return $result;
            } catch (\PDOException $e) {
                if ($this->db->inTransaction()) {
                    $this->db->rollBack();
                }
                // İlk denemede yarış kaynaklı ihlal olabilir → tekrar dene.
                if ($attempt === 0) {
                    continue;
                }
                throw $e;
            }
        }
        // Ulaşılmaz; döngü ya döner ya da fırlatır.
        throw new \RuntimeException('resolveGoogleAccount: beklenmeyen durum');
    }

    /** google_sub → e-posta → yeni hesap sırasıyla çözer. Transaction çağıran sağlar. */
    private function findOrCreateGoogleUser(string $sub, string $email, ?string $name): array
    {
        // 1) Daha önce Google ile bağlanmış hesap.
        $st = $this->db->prepare(
            'SELECT id, email, display_name, username FROM users WHERE google_sub = ?'
        );
        $st->execute([$sub]);
        $u = $st->fetch();
        if ($u) {
            return [
                (int) $u['id'],
                (string) $u['email'],
                $u['display_name'],
                $u['username'],
                false,
            ];
        }

        // 2) Aynı e-postalı mevcut hesap → Google'ı bağla.
        $st = $this->db->prepare(
            'SELECT id, display_name, username FROM users WHERE email = ?'
        );
        $st->execute([$email]);
        $u = $st->fetch();
        if ($u) {
            $uid = (int) $u['id'];
            $up = $this->db->prepare(
                'UPDATE users SET google_sub = ?, updated_at = ? WHERE id = ?'
            );
            $up->execute([$sub, now_ms(), $uid]);
            return [$uid, $email, $u['display_name'], $u['username'], false];
        }

        // 3) Yeni hesap. Parola alanı boş bırakılmaz: rastgele bir secret
        // hash'lenir — bilinmediği için parola girişi imkânsız; kullanıcı isterse
        // "şifremi unuttum" ile parola belirleyebilir.
        $t = now_ms();
        $hash = password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT);
        $ins = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, google_sub, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $ins->execute([$email, $hash, ($name !== null && $name !== '') ? $name : null, $sub, $t, $t]);
        return [(int) $this->db->lastInsertId(), $email, $name, null, true];
    }

    // ─── POST /auth/refresh ─────────────────────────────────────────────────
    public function refresh(array $in): void
    {
        $rt = (string) ($in['refresh_token'] ?? '');
        if ($rt === '') fail(422, 'refresh_token gerekli.');

        $hash = hash('sha256', $rt);
        $st = $this->db->prepare('SELECT user_id, expires_at FROM refresh_tokens WHERE token_hash = ?');
        $st->execute([$hash]);
        $row = $st->fetch();

        if (!$row || (int) $row['expires_at'] < time()) {
            fail(401, 'Geçersiz veya süresi dolmuş yenileme anahtarı.');
        }
        $uid = (int) $row['user_id'];

        // Rotasyon + grace penceresi: eski refresh HEMEN silinmez; ömrü 60
        // saniyeye kısaltılır. Yanıt istemciye ulaşamadan uygulama kapanırsa
        // (mobilde olağan) eski token'la bir kez daha yenileme yapılabilir;
        // aksi halde oturum kalıcı düşerdi. 60 sn sonra token kendiliğinden
        // geçersizleşir (yukarıdaki expires_at kontrolü).
        $graceExpires = min((int) $row['expires_at'], time() + 60);
        $up = $this->db->prepare('UPDATE refresh_tokens SET expires_at = ? WHERE token_hash = ?');
        $up->execute([$graceExpires, $hash]);

        json_out(200, ['tokens' => $this->issueTokens($uid)]);
    }

    // ─── POST /auth/logout ──────────────────────────────────────────────────
    public function logout(array $in): void
    {
        $rt = (string) ($in['refresh_token'] ?? '');
        if ($rt !== '') {
            $del = $this->db->prepare('DELETE FROM refresh_tokens WHERE token_hash = ?');
            $del->execute([hash('sha256', $rt)]);
        }
        json_out(200, ['ok' => true]);
    }

    // ─── GET /me ────────────────────────────────────────────────────────────
    public function me(int $uid): void
    {
        $st = $this->db->prepare('SELECT id, email, display_name, username, is_public FROM users WHERE id = ?');
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u) fail(404, 'Kullanıcı bulunamadı.');
        $u['id'] = (int) $u['id'];
        $u['is_public'] = (int) $u['is_public'];
        json_out(200, $u);
    }

    // ─── POST /auth/change-password (nadir/tekil işlem) ─────────────────────
    public function changePassword(int $uid, array $in): void
    {
        $old = (string) ($in['old_password'] ?? '');
        $new = (string) ($in['new_password'] ?? '');
        if (strlen($new) < 8) fail(422, 'Yeni parola en az 8 karakter olmalı.');

        $st = $this->db->prepare('SELECT password_hash FROM users WHERE id = ?');
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u || !password_verify($old, $u['password_hash'])) {
            fail(401, 'Mevcut parola hatalı.');
        }
        $up = $this->db->prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?');
        $up->execute([password_hash($new, PASSWORD_BCRYPT), now_ms(), $uid]);

        // Güvenlik: parola değişince tüm refresh token'ları iptal et.
        $this->db->prepare('DELETE FROM refresh_tokens WHERE user_id = ?')->execute([$uid]);
        json_out(200, ['ok' => true]);
    }

    // ─── DELETE /me (hesap silme — nadir/tekil işlem) ───────────────────────
    public function deleteAccount(int $uid): void
    {
        // FK ON DELETE CASCADE sayesinde tüm kullanıcı verisi de silinir.
        $this->db->prepare('DELETE FROM users WHERE id = ?')->execute([$uid]);
        json_out(200, ['ok' => true]);
    }

    // ─── POST /auth/forgot-password ──────────────────────────────────────────
    public function forgotPassword(array $in): void
    {
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        if ($email === '') fail(422, 'E-posta adresi gerekli.');

        // Validate email format to prevent header injection/bad input
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            fail(422, 'Geçersiz e-posta formatı.');
        }

        $st = $this->db->prepare('SELECT id FROM users WHERE email = ?');
        $st->execute([$email]);
        $u = $st->fetch();

        // Send 200 OK response instantly to close client connection and eliminate timing attacks
        http_response_code(200);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE);

        if (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }

        // If the user doesn't exist, stop background execution
        if (!$u) {
            return;
        }

        try {
            $code = sprintf('%06d', random_int(0, 999999));
        } catch (Throwable $e) {
            $code = strval(rand(100000, 999999));
        }

        $expiresAt = now_ms() + 15 * 60 * 1000; // 15 mins
        $codeHash = password_hash($code, PASSWORD_BCRYPT);

        try {
            // Fırsatçı temizlik: süresi dolan sıfırlama kodları birikmesin.
            if (mt_rand(1, 20) === 1) {
                $this->db->prepare('DELETE FROM password_resets WHERE expires_at < ?')
                         ->execute([now_ms()]);
            }

            $sel = $this->db->prepare('SELECT 1 FROM password_resets WHERE email = ?');
            $sel->execute([$email]);
            $exists = $sel->fetchColumn();

            $now = now_ms();
            if ($exists) {
                $ups = $this->db->prepare(
                    'UPDATE password_resets
                     SET code_hash = ?, attempts = 0, expires_at = ?, created_at = ?
                     WHERE email = ?'
                );
                $ups->execute([$codeHash, $expiresAt, $now, $email]);
            } else {
                $ups = $this->db->prepare(
                    'INSERT INTO password_resets (email, code_hash, attempts, expires_at, created_at)
                     VALUES (?, ?, 0, ?, ?)'
                );
                $ups->execute([$email, $codeHash, $expiresAt, $now]);
            }

            $smtp = new Smtp(
                $this->cfg['smtp']['host'],
                (int) $this->cfg['smtp']['port'],
                $this->cfg['smtp']['user'],
                $this->cfg['smtp']['pass']
            );

            $subject = "Şifre Sıfırlama Kodu";
            $body = "<h2>Ne İzlesem Şifre Sıfırlama</h2>"
                  . "<p>Hesabınızın şifresini sıfırlamak için geçici kodunuz:</p>"
                  . "<h1 style='color: #FB8C00; font-size: 32px; letter-spacing: 4px; font-family: monospace;'>$code</h1>"
                  . "<p>Bu kod 15 dakika geçerlidir. Eğer bu talebi siz yapmadıysanız lütfen bu e-postayı dikkate almayın.</p>";

            $smtp->send($email, $subject, $body);
        } catch (Throwable $e) {
            cinema_error("Failed to process background password reset for $email: " . $e->getMessage());
        }
    }

    // ─── POST /auth/verify-reset-code ────────────────────────────────────────
    public function verifyResetCode(array $in): void
    {
        // forgotPassword e-postayı lowercase kaydeder; burada da normalize
        // edilmezse case-sensitive collation'larda (ör. SQLite) kod bulunamaz.
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        $code = trim((string) ($in['code'] ?? ''));

        if ($email === '' || $code === '') {
            fail(422, 'E-posta ve doğrulama kodu gereklidir.');
        }

        $st = $this->db->prepare('SELECT code_hash, attempts, expires_at FROM password_resets WHERE email = ?');
        $st->execute([$email]);
        $row = $st->fetch();

        if (!$row || now_ms() > (int) $row['expires_at']) {
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        $attempts = (int) $row['attempts'];
        if ($attempts >= 3) {
            $del = $this->db->prepare('DELETE FROM password_resets WHERE email = ?');
            $del->execute([$email]);
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        // Increment attempts
        $up = $this->db->prepare('UPDATE password_resets SET attempts = attempts + 1 WHERE email = ?');
        $up->execute([$email]);

        if (!password_verify($code, $row['code_hash'])) {
            if ($attempts + 1 >= 3) {
                $del = $this->db->prepare('DELETE FROM password_resets WHERE email = ?');
                $del->execute([$email]);
            }
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        json_out(200, ['ok' => true]);
    }

    // ─── POST /auth/reset-password ───────────────────────────────────────────
    public function resetPassword(array $in): void
    {
        // Bkz. verifyResetCode: e-posta lowercase normalize edilir.
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        $code = trim((string) ($in['code'] ?? ''));
        $newPass = (string) ($in['new_password'] ?? '');

        if ($email === '' || $code === '' || $newPass === '') {
            fail(422, 'Tüm alanlar gereklidir.');
        }
        if (strlen($newPass) < 8) {
            fail(422, 'Yeni parola en az 8 karakter olmalıdır.');
        }

        $st = $this->db->prepare('SELECT code_hash, attempts, expires_at FROM password_resets WHERE email = ?');
        $st->execute([$email]);
        $row = $st->fetch();

        if (!$row || now_ms() > (int) $row['expires_at']) {
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        $attempts = (int) $row['attempts'];
        if ($attempts >= 3) {
            $del = $this->db->prepare('DELETE FROM password_resets WHERE email = ?');
            $del->execute([$email]);
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        // Increment attempts
        $up = $this->db->prepare('UPDATE password_resets SET attempts = attempts + 1 WHERE email = ?');
        $up->execute([$email]);

        if (!password_verify($code, $row['code_hash'])) {
            if ($attempts + 1 >= 3) {
                $del = $this->db->prepare('DELETE FROM password_resets WHERE email = ?');
                $del->execute([$email]);
            }
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.');
        }

        $upUser = $this->db->prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE email = ?');
        $upUser->execute([password_hash($newPass, PASSWORD_BCRYPT), now_ms(), $email]);

        $delRt = $this->db->prepare(
            'DELETE FROM refresh_tokens WHERE user_id = (SELECT id FROM users WHERE email = ?)'
        );
        $delRt->execute([$email]);

        $delCode = $this->db->prepare('DELETE FROM password_resets WHERE email = ?');
        $delCode->execute([$email]);

        json_out(200, ['ok' => true]);
    }

    // ─── Yardımcı: access + refresh üret, refresh'i hash'leyip sakla ────────
    private function issueTokens(int $uid): array
    {
        $now = time();

        // Fırsatçı temizlik: süresi dolan refresh token'lar başka hiçbir yerde
        // silinmiyordu → tablo sınırsız büyüyordu. ~%5 olasılıkla, 1 günden
        // uzun süredir geçersiz olanlar silinir (grace penceresini etkilemez).
        if (mt_rand(1, 20) === 1) {
            try {
                $this->db->prepare('DELETE FROM refresh_tokens WHERE expires_at < ?')
                         ->execute([$now - 86400]);
            } catch (Throwable $e) {
                cinema_error('refresh_tokens cleanup failed: ' . $e->getMessage());
            }
        }
        $access = Jwt::encode([
            'sub' => $uid,
            'typ' => 'access',
            'iat' => $now,
            'exp' => $now + (int) $this->cfg['access_ttl'],
        ], $this->cfg['jwt_secret']);

        $refresh = bin2hex(random_bytes(32));
        $expires = $now + (int) $this->cfg['refresh_ttl'];
        $ins = $this->db->prepare(
            'INSERT INTO refresh_tokens (user_id, token_hash, expires_at, created_at)
             VALUES (?, ?, ?, ?)'
        );
        $ins->execute([$uid, hash('sha256', $refresh), $expires, now_ms()]);

        return [
            'access_token'  => $access,
            'refresh_token' => $refresh,
            'expires_in'    => (int) $this->cfg['access_ttl'],
        ];
    }
}
