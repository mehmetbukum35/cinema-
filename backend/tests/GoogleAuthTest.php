<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/GoogleAuth.php';

class GoogleAuthTest extends TestCase
{
    private PDO $db;
    private Auth $auth;

    private const CLIENT_ID = 'test-client.apps.googleusercontent.com';

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->exec(
            'CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                display_name TEXT,
                username TEXT,
                google_sub TEXT UNIQUE,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )'
        );
        $this->db->exec(
            'CREATE TABLE refresh_tokens (
                user_id INTEGER NOT NULL,
                token_hash TEXT NOT NULL,
                expires_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            )'
        );
        $this->auth = new Auth($this->db, [
            'jwt_secret' => 'test_jwt_secret_key_123456789_test_jwt_secret',
            'access_ttl' => 3600,
            'refresh_ttl' => 86400,
            'google' => ['client_ids' => [self::CLIENT_ID]],
        ]);
    }

    /** Sahte doğrulayıcı: verilen claim'leri döndürür (ağ yok). */
    private static function verifierWith(?array $claims): callable
    {
        return fn (string $idToken) => $claims;
    }

    private function claims(array $overrides = []): array
    {
        return array_merge([
            'sub' => 'google-sub-1',
            'email' => 'ali@example.com',
            'email_verified' => 'true',
            'name' => 'Ali Veli',
            'aud' => self::CLIENT_ID,
            'iss' => 'https://accounts.google.com',
            'exp' => time() + 3600,
        ], $overrides);
    }

    // ── validateClaims (saf) ────────────────────────────────────────────────

    public function testValidateClaimsAcceptsValidToken(): void
    {
        $this->assertTrue(
            GoogleAuth::validateClaims($this->claims(), [self::CLIENT_ID])
        );
    }

    public function testValidateClaimsRejectsWrongAudience(): void
    {
        // Başka bir uygulama için üretilmiş token bizim API'ye giremez.
        $this->assertFalse(
            GoogleAuth::validateClaims(
                $this->claims(['aud' => 'evil-app.apps.googleusercontent.com']),
                [self::CLIENT_ID]
            )
        );
    }

    public function testValidateClaimsRejectsExpiredToken(): void
    {
        $this->assertFalse(
            GoogleAuth::validateClaims(
                $this->claims(['exp' => time() - 10]),
                [self::CLIENT_ID]
            )
        );
    }

    public function testValidateClaimsRejectsUnverifiedEmail(): void
    {
        $this->assertFalse(
            GoogleAuth::validateClaims(
                $this->claims(['email_verified' => 'false']),
                [self::CLIENT_ID]
            )
        );
    }

    public function testValidateClaimsRejectsWrongIssuer(): void
    {
        $this->assertFalse(
            GoogleAuth::validateClaims(
                $this->claims(['iss' => 'https://evil.example']),
                [self::CLIENT_ID]
            )
        );
    }

    // ── googleLogin (hesap mantığı) ─────────────────────────────────────────

    public function testCreatesNewUserOnFirstGoogleLogin(): void
    {
        $this->auth->googleLogin(
            ['id_token' => 'x'],
            self::verifierWith($this->claims())
        );

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertTrue($body['is_new']);
        $this->assertSame('ali@example.com', $body['user']['email']);
        $this->assertSame('Ali Veli', $body['user']['display_name']);
        $this->assertNotEmpty($body['tokens']['access_token']);

        $row = $this->db
            ->query("SELECT google_sub, password_hash FROM users WHERE email = 'ali@example.com'")
            ->fetch(PDO::FETCH_ASSOC);
        $this->assertSame('google-sub-1', $row['google_sub']);
        // Parola alanı boş değil (rastgele secret hash'i) — parola girişi imkânsız.
        $this->assertNotEmpty($row['password_hash']);
    }

    public function testLinksGoogleToExistingEmailAccount(): void
    {
        $t = time() * 1000;
        $this->db
            ->prepare(
                'INSERT INTO users (email, password_hash, display_name, username, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?)'
            )
            ->execute([
                'ali@example.com',
                password_hash('mevcut-parola', PASSWORD_BCRYPT),
                'Mevcut Ali',
                'mevcutali',
                $t,
                $t,
            ]);

        $this->auth->googleLogin(
            ['id_token' => 'x'],
            self::verifierWith($this->claims())
        );

        $body = TestHelperRegistry::$lastBody;
        $this->assertFalse($body['is_new']);
        // Mevcut hesabın kimliği korunur (Google'daki isim EZMEZ).
        $this->assertSame('Mevcut Ali', $body['user']['display_name']);
        $this->assertSame('mevcutali', $body['user']['username']);

        $sub = $this->db
            ->query("SELECT google_sub FROM users WHERE email = 'ali@example.com'")
            ->fetchColumn();
        $this->assertSame('google-sub-1', $sub);
    }

    public function testReturningGoogleUserMatchedBySubEvenIfEmailChanged(): void
    {
        // İlk giriş
        $this->auth->googleLogin(
            ['id_token' => 'x'],
            self::verifierWith($this->claims())
        );
        TestHelperRegistry::reset();

        // Google tarafında e-posta değişmiş olsa bile sub sabittir → aynı hesap.
        $this->auth->googleLogin(
            ['id_token' => 'x'],
            self::verifierWith($this->claims(['email' => 'yeni@example.com']))
        );

        $body = TestHelperRegistry::$lastBody;
        $this->assertFalse($body['is_new']);
        $this->assertSame('ali@example.com', $body['user']['email']);
        $this->assertSame(
            1,
            (int) $this->db->query('SELECT COUNT(*) FROM users')->fetchColumn()
        );
    }

    public function testRejectsWhenVerifierFails(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(401);
        try {
            $this->auth->googleLogin(
                ['id_token' => 'bogus'],
                self::verifierWith(null)
            );
        } finally {
            $this->assertSame(401, TestHelperRegistry::$lastStatus);
        }
    }

    public function testFailsWhenNotConfigured(): void
    {
        $auth = new Auth($this->db, [
            'jwt_secret' => 'test_jwt_secret_key_123456789_test_jwt_secret',
            'access_ttl' => 3600,
            'refresh_ttl' => 86400,
        ]);
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(500);
        $auth->googleLogin(['id_token' => 'x']);
    }

    public function testUnlinkGoogleRemovesSubWhenPasswordValid(): void
    {
        $pass = 'Password123!';
        $hash = password_hash($pass, PASSWORD_BCRYPT);
        $this->db->exec(
            "INSERT INTO users (email, password_hash, google_sub, created_at, updated_at)
             VALUES ('linked@example.com', " . $this->db->quote($hash) . ", 'google-sub-linked', 1, 1)"
        );
        $uid = (int) $this->db->lastInsertId();

        $this->auth->unlinkGoogle($uid, ['password' => $pass]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);
        $row = $this->db->query("SELECT google_sub FROM users WHERE id = $uid")->fetch();
        $this->assertNull($row['google_sub']);
    }

    public function testUnlinkGoogleRequiresPassword(): void
    {
        $this->db->exec(
            "INSERT INTO users (email, password_hash, google_sub, created_at, updated_at)
             VALUES ('linked@example.com', 'hash', 'google-sub-linked', 1, 1)"
        );
        $uid = (int) $this->db->lastInsertId();

        $this->expectException(TestExitException::class);
        try {
            $this->auth->unlinkGoogle($uid, ['password' => '']);
        } finally {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }
}
