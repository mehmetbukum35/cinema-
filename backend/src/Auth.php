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
    // E-posta doğrulamalı kayıt: hesap `email_verified = 0` olarak açılır,
    // token VERİLMEZ. E-postaya 6 haneli kod gider; oturum ancak
    // POST /auth/verify-email ile kod doğrulanınca açılır. Böylece kimse
    // başkasının e-posta adresiyle kullanılabilir bir hesap açamaz.
    public function register(array $in): void
    {
        $email = strtolower(trim($in['email'] ?? ''));
        $pass  = (string) ($in['password'] ?? '');
        $name  = isset($in['display_name']) ? trim($in['display_name']) : null;

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) fail(422, 'Geçersiz e-posta.', 'email_invalid');
        if (strlen($pass) < 8) fail(422, 'Parola en az 8 karakter olmalı.', 'password_too_short');

        $exists = $this->db->prepare('SELECT id, email_verified FROM users WHERE email = ?');
        $exists->execute([$email]);
        $u = $exists->fetch();

        $t = now_ms();
        $hash = password_hash($pass, PASSWORD_BCRYPT);

        if ($u && (int) $u['email_verified'] === 1) {
            fail(409, 'Bu e-posta zaten kayıtlı.', 'email_exists');
        }

        if ($u) {
            // Doğrulanmamış hesap e-postanın sahibine ait sayılmaz: kaydı kim
            // yeniden denerse parola/isim onunkiyle güncellenir. Hesabı en
            // sonunda kodu doğrulayan (= e-postanın gerçek sahibi) kazanır.
            $up = $this->db->prepare(
                'UPDATE users SET password_hash = ?, display_name = ?, updated_at = ? WHERE id = ?'
            );
            $up->execute([$hash, $name, $t, (int) $u['id']]);
        } else {
            $ins = $this->db->prepare(
                'INSERT INTO users (email, password_hash, display_name, email_verified, created_at, updated_at)
                 VALUES (?, ?, ?, 0, ?, ?)'
            );
            $ins->execute([$email, $hash, $name, $t, $t]);
        }

        // Önce yanıt döner (forgotPassword ile aynı desen), kod arka planda
        // e-postalanır — SMTP gecikmesi istemciyi bekletmez.
        $this->respondThenContinue(200, [
            'ok' => true,
            'pending_verification' => true,
            'email' => $email,
        ]);
        $this->sendVerificationCode($email);
    }

    // ─── POST /auth/verify-email ─────────────────────────────────────────────
    // Kayıtta gönderilen kodu doğrular; başarılıysa hesap doğrulanmış olur ve
    // oturum (token çifti) burada açılır.
    public function verifyEmail(array $in): void
    {
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        $code  = trim((string) ($in['code'] ?? ''));
        if ($email === '' || $code === '') {
            fail(422, 'E-posta ve doğrulama kodu gereklidir.');
        }

        $this->consumeCodeOrFail('email_verifications', $email, $code);

        $st = $this->db->prepare(
            'SELECT id, display_name, username, google_sub FROM users WHERE email = ?'
        );
        $st->execute([$email]);
        $u = $st->fetch();
        if (!$u) fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.', 'verify_code_failed');

        $up = $this->db->prepare('UPDATE users SET email_verified = 1, updated_at = ? WHERE id = ?');
        $up->execute([now_ms(), (int) $u['id']]);
        $this->db->prepare('DELETE FROM email_verifications WHERE email = ?')->execute([$email]);

        $uid = (int) $u['id'];
        json_out(200, [
            'user' => [
                'id' => $uid,
                'email' => $email,
                'display_name' => $u['display_name'],
                'username' => $u['username'],
                'google_sub' => $u['google_sub'],
            ],
            'tokens' => $this->issueTokens($uid),
        ]);
    }

    // ─── POST /auth/resend-verification ──────────────────────────────────────
    // Doğrulama kodunu yeniden gönderir. E-posta varlığını sızdırmamak için
    // her durumda 200 döner (forgotPassword ile aynı ilke).
    public function resendVerification(array $in): void
    {
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            fail(422, 'Geçersiz e-posta formatı.', 'email_invalid');
        }

        $st = $this->db->prepare('SELECT 1 FROM users WHERE email = ? AND email_verified = 0');
        $st->execute([$email]);
        $pending = (bool) $st->fetch();

        $this->respondThenContinue(200, ['ok' => true]);
        if ($pending) {
            $this->sendVerificationCode($email);
        }
    }

    /**
     * 6 haneli doğrulama kodunu üretir, email_verifications'a (bcrypt hash)
     * yazar ve e-postalar. Yanıt çoktan döndüğü için hatalar yalnızca loglanır.
     */
    private function sendVerificationCode(string $email): void
    {
        try {
            $code = sprintf('%06d', random_int(0, 999999));
        } catch (Throwable $e) {
            $code = strval(rand(100000, 999999));
        }

        $expiresAt = now_ms() + 15 * 60 * 1000; // 15 dk
        $codeHash = password_hash($code, PASSWORD_BCRYPT);

        try {
            // Fırsatçı temizlik: süresi dolan kodlar birikmesin.
            if (mt_rand(1, 20) === 1) {
                $this->db->prepare('DELETE FROM email_verifications WHERE expires_at < ?')
                         ->execute([now_ms()]);
            }

            $sel = $this->db->prepare('SELECT 1 FROM email_verifications WHERE email = ?');
            $sel->execute([$email]);
            $now = now_ms();
            if ($sel->fetchColumn()) {
                $this->db->prepare(
                    'UPDATE email_verifications
                     SET code_hash = ?, attempts = 0, expires_at = ?, created_at = ?
                     WHERE email = ?'
                )->execute([$codeHash, $expiresAt, $now, $email]);
            } else {
                $this->db->prepare(
                    'INSERT INTO email_verifications (email, code_hash, attempts, expires_at, created_at)
                     VALUES (?, ?, 0, ?, ?)'
                )->execute([$email, $codeHash, $expiresAt, $now]);
            }

            $smtp = new Smtp(
                $this->cfg['smtp']['host'],
                (int) $this->cfg['smtp']['port'],
                $this->cfg['smtp']['user'],
                $this->cfg['smtp']['pass']
            );

            $subject = "E-posta Doğrulama Kodu";
            $body = "<h2>Cinema+ Üyelik Doğrulama</h2>"
                  . "<p>Hesabınızı doğrulamak için geçici kodunuz:</p>"
                  . "<h1 style='color: #FB8C00; font-size: 32px; letter-spacing: 4px; font-family: monospace;'>$code</h1>"
                  . "<p>Bu kod 15 dakika geçerlidir. Eğer bu kaydı siz yapmadıysanız lütfen bu e-postayı dikkate almayın.</p>";

            $smtp->send($email, $subject, $body);
        } catch (Throwable $e) {
            cinema_error("Failed to send verification code for $email: " . $e->getMessage());
        }
    }

    /**
     * Yanıtı hemen döndürür, çağıranın kalan işi (e-posta gönderimi) arka
     * planda sürer. Test ortamında json_out zaten exit etmez; production'da
     * fastcgi_finish_request bağlantıyı kapatır (bkz. forgotPassword).
     */
    private function respondThenContinue(int $status, array $body): void
    {
        if (defined('PHPUNIT_TESTING') || class_exists('PHPUnit\Framework\TestCase', false)) {
            json_out($status, $body);
            return;
        }
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($body, JSON_UNESCAPED_UNICODE);
        if (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }
    }

    /**
     * Kod tablosundan (password_resets / email_verifications) kodu doğrular:
     * süre + 3 deneme sınırı + bcrypt karşılaştırması. Hatalıysa fail() ile
     * çıkar; başarılıysa sessizce döner (satırı silmek çağırana aittir).
     */
    private function consumeCodeOrFail(string $table, string $email, string $code): void
    {
        $st = $this->db->prepare("SELECT code_hash, attempts, expires_at FROM $table WHERE email = ?");
        $st->execute([$email]);
        $row = $st->fetch();

        if (!$row || now_ms() > (int) $row['expires_at']) {
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.', 'verify_code_failed');
        }

        $attempts = (int) $row['attempts'];
        if ($attempts >= 3) {
            $this->db->prepare("DELETE FROM $table WHERE email = ?")->execute([$email]);
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.', 'verify_code_failed');
        }

        $this->db->prepare("UPDATE $table SET attempts = attempts + 1 WHERE email = ?")->execute([$email]);

        if (!password_verify($code, $row['code_hash'])) {
            if ($attempts + 1 >= 3) {
                $this->db->prepare("DELETE FROM $table WHERE email = ?")->execute([$email]);
            }
            fail(400, 'Geçersiz veya süresi dolmuş doğrulama kodu.', 'verify_code_failed');
        }
    }

    // ─── POST /auth/login ───────────────────────────────────────────────────
    public function login(array $in): void
    {
        $email = strtolower(trim($in['email'] ?? ''));
        $pass  = (string) ($in['password'] ?? '');

        $st = $this->db->prepare('SELECT id, password_hash, display_name, username, google_sub, email_verified FROM users WHERE email = ?');
        $st->execute([$email]);
        $u = $st->fetch();

        if (!$u) {
            // Zamanlama farkıyla e-posta varlığı sızmasın diye kullanıcı yokken
            // de bcrypt maliyeti ödenir (sahte hash ile doğrulama).
            password_verify($pass, '$2y$10$abcdefghijklmnopqrstuv0123456789012345678901234567890');
            fail(401, 'E-posta veya parola hatalı.', 'invalid_credentials');
        }
        if (!password_verify($pass, $u['password_hash'])) {
            fail(401, 'E-posta veya parola hatalı.', 'invalid_credentials');
        }
        if ((int) $u['email_verified'] !== 1) {
            // Kayıt tamamlanmamış: kod doğrulanmadan oturum açılmaz. İstemci bu
            // yanıtla doğrulama ekranını açar (kodu yeniden göndererek).
            fail(403, 'E-posta adresi doğrulanmamış.', 'email_unverified');
        }
        $uid = (int) $u['id'];
        json_out(200, [
            'user'   => [
                'id' => $uid,
                'email' => $email,
                'display_name' => $u['display_name'],
                'username' => $u['username'],
                'google_sub' => $u['google_sub'],
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
            fail(401, 'Google kimliği doğrulanamadı.', 'google_failed');
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
                'google_sub' => $sub,
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
            'SELECT id, display_name, username, email_verified FROM users WHERE email = ?'
        );
        $st->execute([$email]);
        $u = $st->fetch();
        if ($u) {
            $uid = (int) $u['id'];
            if ((int) $u['email_verified'] === 1) {
                $up = $this->db->prepare(
                    'UPDATE users SET google_sub = ?, updated_at = ? WHERE id = ?'
                );
                $up->execute([$sub, now_ms(), $uid]);
                return [$uid, $email, $u['display_name'], $u['username'], false];
            }

            // Doğrulanmamış hesap: e-postanın sahibi olduğu hiç kanıtlanmadı —
            // kaydı başkası (ör. bu adresi gasp etmeye çalışan biri) açmış
            // olabilir. Google e-postayı doğruladığı için gerçek sahip şu anki
            // kullanıcıdır: hesap ona devredilir; eski parola rastgele bir
            // secret ile geçersizleştirilir ve olası oturumlar düşürülür.
            $up = $this->db->prepare(
                'UPDATE users SET google_sub = ?, email_verified = 1, password_hash = ?,
                        display_name = ?, updated_at = ? WHERE id = ?'
            );
            $up->execute([
                $sub,
                password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT),
                ($name !== null && $name !== '') ? $name : $u['display_name'],
                now_ms(),
                $uid,
            ]);
            $this->db->prepare('DELETE FROM refresh_tokens WHERE user_id = ?')->execute([$uid]);
            $this->db->prepare('DELETE FROM email_verifications WHERE email = ?')->execute([$email]);
            return [$uid, $email, ($name !== null && $name !== '') ? $name : $u['display_name'], $u['username'], false];
        }

        // 3) Yeni hesap. Parola alanı boş bırakılmaz: rastgele bir secret
        // hash'lenir — bilinmediği için parola girişi imkânsız; kullanıcı isterse
        // "şifremi unuttum" ile parola belirleyebilir. Google e-postayı
        // doğruladığı için hesap doğrulanmış açılır.
        $t = now_ms();
        $hash = password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT);
        $ins = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, google_sub, email_verified, created_at, updated_at)
             VALUES (?, ?, ?, ?, 1, ?, ?)'
        );
        $ins->execute([$email, $hash, ($name !== null && $name !== '') ? $name : null, $sub, $t, $t]);
        return [(int) $this->db->lastInsertId(), $email, $name, null, true];
    }

    // ─── POST /auth/apple ───────────────────────────────────────────────────
    // Sign in with Apple: istemcinin gönderdiği identity token doğrulanır,
    // kullanıcı apple_sub ile bulunur; yoksa AYNI e-postalı hesaba bağlanır
    // (Apple e-postayı doğruladığı için güvenli); o da yoksa yeni hesap açılır.
    // Ad, token'da bulunmaz: istemci İLK yetkilendirmede display_name gönderir.
    // $verifier: testler için enjekte edilebilir (identityToken → claims|null).
    public function appleLogin(array $in, ?callable $verifier = null): void
    {
        $idToken = (string) ($in['identity_token'] ?? '');
        if ($idToken === '') {
            fail(422, 'identity_token gerekli.');
        }

        $bundleIds = (array) ($this->cfg['apple']['bundle_ids'] ?? []);
        if ($bundleIds === []) {
            fail(500, 'Apple girişi sunucuda yapılandırılmamış (apple.bundle_ids eksik).');
        }

        $verifier ??= fn (string $t) => AppleAuth::verifyIdentityToken($t, $bundleIds);
        $claims = $verifier($idToken);
        if ($claims === null) {
            fail(401, 'Apple kimliği doğrulanamadı.', 'apple_failed');
        }

        $sub = (string) $claims['sub'];
        $email = strtolower(trim((string) ($claims['email'] ?? '')));
        $name = isset($in['display_name']) ? trim((string) $in['display_name']) : null;

        [$uid, $email, $name, $username, $isNew] =
            $this->resolveAppleAccount($sub, $email, $name);

        json_out(200, [
            'user' => [
                'id' => $uid,
                'email' => $email,
                'display_name' => $name,
                'username' => $username,
                'apple_sub' => $sub,
            ],
            'tokens' => $this->issueTokens($uid),
            'is_new' => $isNew,
        ]);
    }

    /** resolveGoogleAccount'un Apple eşleniği: transaction + tek retry. */
    private function resolveAppleAccount(string $sub, string $email, ?string $name): array
    {
        for ($attempt = 0; $attempt < 2; $attempt++) {
            try {
                $this->db->beginTransaction();
                $result = $this->findOrCreateAppleUser($sub, $email, $name);
                $this->db->commit();
                return $result;
            } catch (\PDOException $e) {
                if ($this->db->inTransaction()) {
                    $this->db->rollBack();
                }
                if ($attempt === 0) {
                    continue;
                }
                throw $e;
            }
        }
        throw new \RuntimeException('resolveAppleAccount: beklenmeyen durum');
    }

    /** apple_sub → e-posta → yeni hesap sırasıyla çözer. Transaction çağıran sağlar. */
    private function findOrCreateAppleUser(string $sub, string $email, ?string $name): array
    {
        // 1) Daha önce Apple ile bağlanmış hesap.
        $st = $this->db->prepare(
            'SELECT id, email, display_name, username FROM users WHERE apple_sub = ?'
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

        // Yeni bağlama/hesap için e-posta şart. Apple, e-postayı yalnızca
        // kullanıcı izin verdiyse token'a koyar; izin daha önce verilip claim
        // yine de gelmediyse kullanıcı Apple ID ayarlarından uygulama iznini
        // kaldırıp yeniden denemelidir.
        if ($email === '') {
            fail(422, 'Apple hesabınızdan e-posta alınamadı. Apple ID ayarlarından '
                . '"Apple ile Oturum Açma" iznini kaldırıp tekrar deneyin.');
        }

        // 2) Aynı e-postalı mevcut hesap → Apple'ı bağla.
        $st = $this->db->prepare(
            'SELECT id, display_name, username, email_verified FROM users WHERE email = ?'
        );
        $st->execute([$email]);
        $u = $st->fetch();
        if ($u) {
            $uid = (int) $u['id'];
            if ((int) $u['email_verified'] === 1) {
                $up = $this->db->prepare(
                    'UPDATE users SET apple_sub = ?, updated_at = ? WHERE id = ?'
                );
                $up->execute([$sub, now_ms(), $uid]);
                return [$uid, $email, $u['display_name'], $u['username'], false];
            }

            // Doğrulanmamış hesap: e-postanın gerçek sahibi şu anki kullanıcı
            // (Apple doğruladı) → hesap ona devredilir (Google akışıyla aynı).
            $up = $this->db->prepare(
                'UPDATE users SET apple_sub = ?, email_verified = 1, password_hash = ?,
                        display_name = ?, updated_at = ? WHERE id = ?'
            );
            $up->execute([
                $sub,
                password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT),
                ($name !== null && $name !== '') ? $name : $u['display_name'],
                now_ms(),
                $uid,
            ]);
            $this->db->prepare('DELETE FROM refresh_tokens WHERE user_id = ?')->execute([$uid]);
            $this->db->prepare('DELETE FROM email_verifications WHERE email = ?')->execute([$email]);
            return [$uid, $email, ($name !== null && $name !== '') ? $name : $u['display_name'], $u['username'], false];
        }

        // 3) Yeni hesap (Google akışıyla aynı: rastgele parola, doğrulanmış).
        $t = now_ms();
        $hash = password_hash(bin2hex(random_bytes(32)), PASSWORD_BCRYPT);
        $ins = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, apple_sub, email_verified, created_at, updated_at)
             VALUES (?, ?, ?, ?, 1, ?, ?)'
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
        $st = $this->db->prepare(
            'SELECT id, email, display_name, username, is_public, google_sub, apple_sub FROM users WHERE id = ?'
        );
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u) fail(404, 'Kullanıcı bulunamadı.', 'user_not_found');
        $u['id'] = (int) $u['id'];
        $u['is_public'] = (int) $u['is_public'];
        json_out(200, $u);
    }

    // ─── DELETE /auth/google/link *(Bearer)* ─────────────────────────────────
    // Google hesabı bağlantısını kaldırır. Parola ile giriş mümkün olan hesaplarda
    // mevcut parola zorunludur.
    public function unlinkGoogle(int $uid, array $in): void
    {
        $st = $this->db->prepare('SELECT google_sub, password_hash FROM users WHERE id = ?');
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u || empty($u['google_sub'])) {
            fail(422, 'Bağlı Google hesabı yok.', 'google_unlink_failed');
        }

        $pass = (string) ($in['password'] ?? '');
        if ($pass === '') {
            fail(422, 'Bağlantıyı kaldırmak için parola gerekli.', 'google_unlink_failed');
        }
        if (!password_verify($pass, $u['password_hash'])) {
            fail(401, 'Mevcut parola hatalı.', 'wrong_password');
        }

        $up = $this->db->prepare('UPDATE users SET google_sub = NULL, updated_at = ? WHERE id = ?');
        $up->execute([now_ms(), $uid]);
        json_out(200, ['ok' => true]);
    }

    // ─── DELETE /auth/apple/link *(Bearer)* ──────────────────────────────────
    // Apple hesabı bağlantısını kaldırır. Parola ile giriş mümkün olan hesaplarda
    // mevcut parola zorunludur.
    public function unlinkApple(int $uid, array $in): void
    {
        $st = $this->db->prepare('SELECT apple_sub, password_hash FROM users WHERE id = ?');
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u || empty($u['apple_sub'])) {
            fail(422, 'Bağlı Apple hesabı yok.', 'apple_unlink_failed');
        }

        $pass = (string) ($in['password'] ?? '');
        if ($pass === '') {
            fail(422, 'Bağlantıyı kaldırmak için parola gerekli.', 'apple_unlink_failed');
        }
        if (!password_verify($pass, $u['password_hash'])) {
            fail(401, 'Mevcut parola hatalı.', 'wrong_password');
        }

        $up = $this->db->prepare('UPDATE users SET apple_sub = NULL, updated_at = ? WHERE id = ?');
        $up->execute([now_ms(), $uid]);
        json_out(200, ['ok' => true]);
    }
     // ─── POST /auth/change-password (nadir/tekil işlem) ─────────────────────
    public function changePassword(int $uid, array $in): void
    {
        $old = (string) ($in['old_password'] ?? '');
        $new = (string) ($in['new_password'] ?? '');
        if (strlen($new) < 8) fail(422, 'Yeni parola en az 8 karakter olmalı.', 'password_too_short');

        $st = $this->db->prepare('SELECT password_hash FROM users WHERE id = ?');
        $st->execute([$uid]);
        $u = $st->fetch();
        if (!$u || !password_verify($old, $u['password_hash'])) {
            fail(401, 'Mevcut parola hatalı.', 'wrong_password');
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
        if ($email === '') fail(422, 'E-posta adresi gerekli.', 'email_invalid');

        // Validate email format to prevent header injection/bad input
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            fail(422, 'Geçersiz e-posta formatı.', 'email_invalid');
        }

        $st = $this->db->prepare('SELECT id FROM users WHERE email = ?');
        $st->execute([$email]);
        $u = $st->fetch();

        // Send 200 OK response instantly to close client connection and eliminate timing attacks
        if (function_exists('json_out') && (defined('PHPUNIT_TESTING') || class_exists('PHPUnit\Framework\TestCase', false))) {
            json_out(200, ['ok' => true]);
        } else {
            http_response_code(200);
            header('Content-Type: application/json; charset=utf-8');
            echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE);
            if (function_exists('fastcgi_finish_request')) {
                fastcgi_finish_request();
            }
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
            $body = "<h2>Cinema+ Şifre Sıfırlama</h2>"
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

        $this->consumeCodeOrFail('password_resets', $email, $code);

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
            fail(422, 'Yeni parola en az 8 karakter olmalıdır.', 'password_too_short');
        }

        $this->consumeCodeOrFail('password_resets', $email, $code);

        // Kod e-postaya gittiği için sahiplik kanıtlanmıştır: parolayla birlikte
        // hesap doğrulanmış da işaretlenir (doğrulanmamış hesabın gerçek sahibi
        // hesabı bu yolla da geri alabilir).
        $upUser = $this->db->prepare('UPDATE users SET password_hash = ?, email_verified = 1, updated_at = ? WHERE email = ?');
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
