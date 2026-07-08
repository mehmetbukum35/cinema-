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
    }

    private function seedUser(string $email, string $pass = 'password123'): int
    {
        $hash = password_hash($pass, PASSWORD_BCRYPT);
        $t = (int) round(microtime(true) * 1000);
        $st = $this->db->prepare(
            'INSERT INTO users (email, password_hash, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
        );
        $st->execute([$email, $hash, 'Test User', $t, $t]);
        return (int) $this->db->lastInsertId();
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
