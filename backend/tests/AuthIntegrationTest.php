<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

class AuthIntegrationTest extends TestCase
{
    private PDO $db;
    private Auth $auth;
    private array $cfg;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        
        $this->createSchema();
        
        $this->cfg = [
            'jwt_secret' => 'test_jwt_secret_key_123456789_test_jwt_secret',
            'access_ttl' => 3600,
            'refresh_ttl' => 86400 * 30,
            'smtp' => [
                'host' => 'localhost',
                'port' => 25,
                'user' => 'test@example.com',
                'pass' => 'test',
            ]
        ];
        
        $this->auth = new Auth($this->db, $this->cfg);
    }

    private function createSchema(): void
    {
        $this->db->exec(
            'CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name TEXT,
                username TEXT UNIQUE,
                google_sub TEXT UNIQUE,
                taste_dna TEXT,
                taste_dna_at INTEGER DEFAULT 0,
                email_verified INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER,
                updated_at INTEGER
            )'
        );
        $this->db->exec(
            'CREATE TABLE refresh_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                token_hash TEXT UNIQUE NOT NULL,
                expires_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            )'
        );
        $this->db->exec(
            'CREATE TABLE password_resets (
                email TEXT PRIMARY KEY,
                code_hash TEXT NOT NULL,
                attempts INTEGER DEFAULT 0,
                expires_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            )'
        );
        $this->db->exec(
            'CREATE TABLE email_verifications (
                email TEXT PRIMARY KEY,
                code_hash TEXT NOT NULL,
                attempts INTEGER DEFAULT 0,
                expires_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL
            )'
        );
    }

    private function seedUser(string $email, string $pass = 'password123', int $verified = 1): int
    {
        $hash = password_hash($pass, PASSWORD_BCRYPT);
        $t = (int) round(microtime(true) * 1000);
        $st = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, email_verified, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
        );
        $st->execute([$email, $hash, 'Test User', $verified, $t, $t]);
        return (int) $this->db->lastInsertId();
    }

    /** email_verifications'taki kodu bilinen bir değere sabitler (bcrypt saklandığı için). */
    private function forceVerificationCode(string $email, string $code): void
    {
        $this->db->prepare('UPDATE email_verifications SET code_hash = ? WHERE email = ?')
                 ->execute([password_hash($code, PASSWORD_BCRYPT), $email]);
    }

    // ── Kayıt + e-posta doğrulama akışı ─────────────────────────────────────

    public function testRegisterCreatesUnverifiedUserWithCodeAndNoTokens(): void
    {
        $this->auth->register([
            'email' => 'yeni@example.com',
            'password' => 'password123',
            'display_name' => 'Yeni Üye',
        ]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertTrue($body['pending_verification']);
        $this->assertArrayNotHasKey('tokens', $body);

        $row = $this->db->query("SELECT email_verified FROM users WHERE email = 'yeni@example.com'")->fetch();
        $this->assertSame(0, (int) $row['email_verified']);

        $codes = $this->db->query("SELECT COUNT(*) FROM email_verifications WHERE email = 'yeni@example.com'")->fetchColumn();
        $this->assertSame(1, (int) $codes);
    }

    public function testUnverifiedUserCannotLogin(): void
    {
        $this->auth->register(['email' => 'yeni@example.com', 'password' => 'password123']);

        try {
            $this->auth->login(['email' => 'yeni@example.com', 'password' => 'password123']);
            $this->fail('Doğrulanmamış hesap giriş yapamamalı');
        } catch (TestExitException $e) {
            $this->assertSame(403, TestHelperRegistry::$lastStatus);
            $this->assertSame('E-posta adresi doğrulanmamış.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testVerifyEmailMarksVerifiedAndIssuesTokens(): void
    {
        $this->auth->register([
            'email' => 'yeni@example.com',
            'password' => 'password123',
            'display_name' => 'Yeni Üye',
        ]);
        $this->forceVerificationCode('yeni@example.com', '123456');

        TestHelperRegistry::reset();
        $this->auth->verifyEmail(['email' => 'yeni@example.com', 'code' => '123456']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertSame('yeni@example.com', $body['user']['email']);
        $this->assertNotEmpty($body['tokens']['access_token']);

        $row = $this->db->query("SELECT email_verified FROM users WHERE email = 'yeni@example.com'")->fetch();
        $this->assertSame(1, (int) $row['email_verified']);

        // Kod tek kullanımlık: satır silinmiş olmalı.
        $codes = $this->db->query('SELECT COUNT(*) FROM email_verifications')->fetchColumn();
        $this->assertSame(0, (int) $codes);

        // Artık normal giriş de çalışır.
        TestHelperRegistry::reset();
        $this->auth->login(['email' => 'yeni@example.com', 'password' => 'password123']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
    }

    public function testVerifyEmailRejectsWrongCodeAndLimitsAttempts(): void
    {
        $this->auth->register(['email' => 'yeni@example.com', 'password' => 'password123']);

        for ($i = 1; $i <= 3; $i++) {
            try {
                $this->auth->verifyEmail(['email' => 'yeni@example.com', 'code' => '000000']);
                $this->fail('Yanlış kod kabul edilmemeli');
            } catch (TestExitException $e) {
                $this->assertSame(400, TestHelperRegistry::$lastStatus);
            }
        }

        // 3 hatalı denemeden sonra kod silinir.
        $codes = $this->db->query('SELECT COUNT(*) FROM email_verifications')->fetchColumn();
        $this->assertSame(0, (int) $codes);
    }

    public function testReRegisterOverwritesUnverifiedAccount(): void
    {
        // Saldırgan kurbanın e-postasıyla kayıt olur (doğrulayamaz).
        $this->auth->register(['email' => 'kurban@example.com', 'password' => 'attacker-pass', 'display_name' => 'Sahte']);

        // Gerçek sahip aynı e-postayla kayıt olur → 409 yerine hesap ona devredilir.
        TestHelperRegistry::reset();
        $this->auth->register(['email' => 'kurban@example.com', 'password' => 'owner-pass-123', 'display_name' => 'Gerçek Sahip']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['pending_verification']);

        // Tek hesap var; parola artık sahibinki.
        $this->assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM users')->fetchColumn());
        $hash = $this->db->query("SELECT password_hash FROM users WHERE email = 'kurban@example.com'")->fetchColumn();
        $this->assertTrue(password_verify('owner-pass-123', $hash));
        $this->assertFalse(password_verify('attacker-pass', $hash));
    }

    public function testResendVerificationAlwaysReturns200(): void
    {
        $this->auth->register(['email' => 'yeni@example.com', 'password' => 'password123']);
        $this->db->exec('DELETE FROM email_verifications');

        TestHelperRegistry::reset();
        $this->auth->resendVerification(['email' => 'yeni@example.com']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM email_verifications')->fetchColumn());

        // Kayıtlı olmayan e-posta: yine 200, kod üretilmez (varlık sızdırılmaz).
        TestHelperRegistry::reset();
        $this->auth->resendVerification(['email' => 'yok@example.com']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $codes = $this->db->query("SELECT COUNT(*) FROM email_verifications WHERE email = 'yok@example.com'")->fetchColumn();
        $this->assertSame(0, (int) $codes);
    }

    public function testResetPasswordAlsoVerifiesEmail(): void
    {
        // Doğrulanmamış hesabın gerçek sahibi "şifremi unuttum" ile hesabı geri alır.
        $this->seedUser('sahip@example.com', 'attacker-pass', 0);
        $this->auth->forgotPassword(['email' => 'sahip@example.com']);

        $knownHash = password_hash('123456', PASSWORD_BCRYPT);
        $this->db->prepare('UPDATE password_resets SET code_hash = ? WHERE email = ?')
                 ->execute([$knownHash, 'sahip@example.com']);

        TestHelperRegistry::reset();
        $this->auth->resetPassword([
            'email' => 'sahip@example.com',
            'code' => '123456',
            'new_password' => 'owner-pass-123',
        ]);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);

        $row = $this->db->query("SELECT email_verified FROM users WHERE email = 'sahip@example.com'")->fetch();
        $this->assertSame(1, (int) $row['email_verified']);
    }

    public function testForgotPasswordAlwaysReturns200(): void
    {
        // 1) Existing user
        $this->seedUser('alice@example.com');
        
        $this->auth->forgotPassword(['email' => 'alice@example.com']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);

        // Check reset code was generated
        $st = $this->db->prepare('SELECT COUNT(*) FROM password_resets WHERE email = ?');
        $st->execute(['alice@example.com']);
        $this->assertSame(1, (int) $st->fetchColumn());

        // 2) Non-existing user
        TestHelperRegistry::reset();
        $this->auth->forgotPassword(['email' => 'nonexistent@example.com']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);

        // Check no reset code was generated for nonexistent user
        $st = $this->db->prepare('SELECT COUNT(*) FROM password_resets WHERE email = ?');
        $st->execute(['nonexistent@example.com']);
        $this->assertSame(0, (int) $st->fetchColumn());
    }

    public function testVerifyResetCodeMaxAttempts(): void
    {
        $email = 'bob@example.com';
        $this->seedUser($email);

        // Generate reset code
        $this->auth->forgotPassword(['email' => $email]);
        
        // Find code in DB (since it's hashed, we fetch the row and attempt verification)
        $row = $this->db->query('SELECT * FROM password_resets')->fetch();
        $this->assertNotEmpty($row);

        // Try wrong code 1st attempt
        try {
            $this->auth->verifyResetCode(['email' => $email, 'code' => '000000']);
            $this->fail('Should fail on wrong code');
        } catch (TestExitException $e) {
            $this->assertSame(400, TestHelperRegistry::$lastStatus);
            $this->assertSame('Geçersiz veya süresi dolmuş doğrulama kodu.', TestHelperRegistry::$lastBody['error']);
        }

        // Check attempts incremented to 1
        $attempts = $this->db->query('SELECT attempts FROM password_resets')->fetchColumn();
        $this->assertSame(1, (int) $attempts);

        // Try wrong code 2nd attempt
        try {
            $this->auth->verifyResetCode(['email' => $email, 'code' => '000000']);
            $this->fail('Should fail on wrong code');
        } catch (TestExitException $e) {
            $this->assertSame(400, TestHelperRegistry::$lastStatus);
        }

        // Check attempts incremented to 2
        $attempts = $this->db->query('SELECT attempts FROM password_resets')->fetchColumn();
        $this->assertSame(2, (int) $attempts);

        // Try wrong code 3rd attempt
        try {
            $this->auth->verifyResetCode(['email' => $email, 'code' => '000000']);
            $this->fail('Should fail on wrong code and delete the code record');
        } catch (TestExitException $e) {
            $this->assertSame(400, TestHelperRegistry::$lastStatus);
        }

        // Verify the reset code row is now deleted from DB after 3 failed attempts
        $rowAfter = $this->db->query('SELECT * FROM password_resets')->fetch();
        $this->assertFalse($rowAfter);
    }

    public function testResetPasswordRevokesRefreshTokens(): void
    {
        $email = 'charlie@example.com';
        $uid = $this->seedUser($email);

        // Seed some refresh tokens for user
        $stmtToken = $this->db->prepare('INSERT INTO refresh_tokens (user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?)');
        $stmtToken->execute([$uid, 'token1_hash', time() + 3600, time()]);
        $stmtToken->execute([$uid, 'token2_hash', time() + 3600, time()]);

        // Verify tokens exist
        $st = $this->db->prepare('SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ?');
        $st->execute([$uid]);
        $this->assertSame(2, (int) $st->fetchColumn());

        // Generate reset code
        $this->auth->forgotPassword(['email' => $email]);

        // Retrieve the generated code (hashed in DB)
        // Since password_verify requires code, let's manually mock the verification path
        // or extract it. Wait, since password_resets stores bcrypt hash, we can bypass
        // the random code generation or retrieve it. Wait!
        // Instead of random, let's update password_resets code_hash to a known code hash!
        $knownCode = '123456';
        $knownHash = password_hash($knownCode, PASSWORD_BCRYPT);
        $this->db->prepare('UPDATE password_resets SET code_hash = ? WHERE email = ?')->execute([$knownHash, $email]);

        // Reset password using the correct code
        TestHelperRegistry::reset();
        $this->auth->resetPassword([
            'email' => $email,
            'code' => $knownCode,
            'new_password' => 'newpassword123'
        ]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);

        // Verify user's password_hash was updated
        $newHash = $this->db->query('SELECT password_hash FROM users WHERE id = ' . $uid)->fetchColumn();
        $this->assertTrue(password_verify('newpassword123', $newHash));

        // Verify refresh tokens are deleted
        $st->execute([$uid]);
        $this->assertSame(0, (int) $st->fetchColumn());

        // Verify reset code is deleted
        $codeCount = $this->db->query('SELECT COUNT(*) FROM password_resets')->fetchColumn();
        $this->assertSame(0, (int) $codeCount);
    }
}
