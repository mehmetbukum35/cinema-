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

        if (!$u || !password_verify($pass, $u['password_hash'])) {
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

        // Rotasyon: eski refresh'i sil, yenilerini ver.
        $del = $this->db->prepare('DELETE FROM refresh_tokens WHERE token_hash = ?');
        $del->execute([$hash]);

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
        $email = trim((string) ($in['email'] ?? ''));
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
        $email = trim((string) ($in['email'] ?? ''));
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
