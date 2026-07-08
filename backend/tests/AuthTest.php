<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

class AuthTest extends TestCase
{
    private $db;
    private $cfg;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = $this->createMock(PDO::class);
        $this->cfg = [
            'jwt_secret' => 'test_jwt_secret_key_123456789_test_jwt_secret',
            'access_ttl' => 3600,
            'refresh_ttl' => 86400 * 30,
        ];
    }

    public function testLoginSuccess(): void
    {
        $email = 'user@example.com';
        $password = 'password123';
        $hashed = password_hash($password, PASSWORD_BCRYPT);

        // Mock statement for SELECT user
        $stmtUser = $this->createMock(PDOStatement::class);
        $stmtUser->method('fetch')->willReturn([
            'id' => '42',
            'password_hash' => $hashed,
            'display_name' => 'John Doe',
            'username' => 'johndoe',
        ]);

        // Mock statement for INSERT refresh token
        $stmtToken = $this->createMock(PDOStatement::class);

        // Configure PDO mock
        $this->db->method('prepare')->willReturnCallback(function ($sql) use ($stmtUser, $stmtToken) {
            if (str_contains($sql, 'SELECT id, password_hash')) {
                return $stmtUser;
            }
            if (str_contains($sql, 'INSERT INTO refresh_tokens')) {
                return $stmtToken;
            }
            return $this->createMock(PDOStatement::class);
        });

        $auth = new Auth($this->db, $this->cfg);
        $auth->login(['email' => $email, 'password' => $password]);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertEquals(42, $body['user']['id']);
        $this->assertEquals('John Doe', $body['user']['display_name']);
        $this->assertArrayHasKey('tokens', $body);
        $this->assertNotEmpty($body['tokens']['access_token']);
        $this->assertNotEmpty($body['tokens']['refresh_token']);
    }

    public function testLoginWrongPasswordThrowsException(): void
    {
        $email = 'user@example.com';
        $password = 'password123';
        $hashed = password_hash('correct_password', PASSWORD_BCRYPT);

        $stmtUser = $this->createMock(PDOStatement::class);
        $stmtUser->method('fetch')->willReturn([
            'id' => '42',
            'password_hash' => $hashed,
            'display_name' => 'John Doe',
            'username' => 'johndoe',
        ]);

        $this->db->method('prepare')->willReturn($stmtUser);

        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(401);

        try {
            $auth->login(['email' => $email, 'password' => $password]);
        } finally {
            $this->assertEquals(401, TestHelperRegistry::$lastStatus);
            $this->assertEquals('E-posta veya parola hatalı.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testRegisterValidationFailsOnInvalidEmail(): void
    {
        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);

        try {
            $auth->register(['email' => 'invalid-email', 'password' => '12345678']);
        } finally {
            $this->assertEquals(422, TestHelperRegistry::$lastStatus);
            $this->assertEquals('Geçersiz e-posta.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testRegisterValidationFailsOnShortPassword(): void
    {
        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);

        try {
            $auth->register(['email' => 'test@example.com', 'password' => 'short']);
        } finally {
            $this->assertEquals(422, TestHelperRegistry::$lastStatus);
            $this->assertEquals('Parola en az 8 karakter olmalı.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testRegisterSuccess(): void
    {
        $email = 'new@example.com';
        $password = 'password123';

        // exists query returns false
        $stmtExists = $this->createMock(PDOStatement::class);
        $stmtExists->method('fetch')->willReturn(false);

        // insert user stmt
        $stmtInsertUser = $this->createMock(PDOStatement::class);
        
        // token insert stmt
        $stmtToken = $this->createMock(PDOStatement::class);

        $this->db->method('prepare')->willReturnCallback(function ($sql) use ($stmtExists, $stmtInsertUser, $stmtToken) {
            if (str_contains($sql, 'SELECT 1 FROM users')) {
                return $stmtExists;
            }
            if (str_contains($sql, 'INSERT INTO users')) {
                return $stmtInsertUser;
            }
            if (str_contains($sql, 'INSERT INTO refresh_tokens')) {
                return $stmtToken;
            }
            return $this->createMock(PDOStatement::class);
        });

        // Set lastInsertId
        $this->db->method('lastInsertId')->willReturn('101');

        $auth = new Auth($this->db, $this->cfg);
        $auth->register(['email' => $email, 'password' => $password, 'display_name' => 'New User']);

        $this->assertEquals(201, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertEquals(101, $body['user']['id']);
        $this->assertEquals('new@example.com', $body['user']['email']);
        $this->assertArrayHasKey('tokens', $body);
    }

    public function testLogout(): void
    {
        $stmt = $this->createMock(PDOStatement::class);
        $this->db->method('prepare')->willReturn($stmt);

        $auth = new Auth($this->db, $this->cfg);
        $auth->logout(['refresh_token' => 'some_token']);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $this->assertEquals(['ok' => true], TestHelperRegistry::$lastBody);
    }

    public function testDeleteAccount(): void
    {
        $stmt = $this->createMock(PDOStatement::class);
        $this->db->method('prepare')->willReturn($stmt);

        $auth = new Auth($this->db, $this->cfg);
        $auth->deleteAccount(42);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $this->assertEquals(['ok' => true], TestHelperRegistry::$lastBody);
    }

    public function testChangePasswordSuccess(): void
    {
        $uid = 42;
        $hashed = password_hash('old_pass_123', PASSWORD_BCRYPT);

        // Select stmt returns current password hash
        $stmtSelect = $this->createMock(PDOStatement::class);
        $stmtSelect->method('fetch')->willReturn(['password_hash' => $hashed]);

        // Update stmt and Delete stmt
        $stmtUpdate = $this->createMock(PDOStatement::class);
        $stmtDelete = $this->createMock(PDOStatement::class);

        $this->db->method('prepare')->willReturnCallback(function ($sql) use ($stmtSelect, $stmtUpdate, $stmtDelete) {
            if (str_contains($sql, 'SELECT password_hash')) {
                return $stmtSelect;
            }
            if (str_contains($sql, 'UPDATE users SET password_hash')) {
                return $stmtUpdate;
            }
            if (str_contains($sql, 'DELETE FROM refresh_tokens')) {
                return $stmtDelete;
            }
            return $this->createMock(PDOStatement::class);
        });

        $auth = new Auth($this->db, $this->cfg);
        $auth->changePassword($uid, ['old_password' => 'old_pass_123', 'new_password' => 'new_pass_123']);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $this->assertEquals(['ok' => true], TestHelperRegistry::$lastBody);
    }

    public function testChangePasswordWrongOldPasswordThrows(): void
    {
        $uid = 42;
        $hashed = password_hash('correct_password', PASSWORD_BCRYPT);

        $stmtSelect = $this->createMock(PDOStatement::class);
        $stmtSelect->method('fetch')->willReturn(['password_hash' => $hashed]);

        $this->db->method('prepare')->willReturn($stmtSelect);

        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(401);

        try {
            $auth->changePassword($uid, ['old_password' => 'wrong_password', 'new_password' => 'new_pass_123']);
        } finally {
            $this->assertEquals(401, TestHelperRegistry::$lastStatus);
            $this->assertEquals('Mevcut parola hatalı.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testRefreshSuccess(): void
    {
        $rt = 'some_refresh_token';
        $hash = hash('sha256', $rt);

        // Select stmt returns user_id and valid expires_at
        $stmtSelect = $this->createMock(PDOStatement::class);
        $stmtSelect->method('fetch')->willReturn([
            'user_id' => '42',
            'expires_at' => time() + 3600,
        ]);

        // Update stmt for grace period
        $stmtUpdate = $this->createMock(PDOStatement::class);

        // Insert new token stmt (called inside issueTokens)
        $stmtInsert = $this->createMock(PDOStatement::class);

        $this->db->method('prepare')->willReturnCallback(function ($sql) use ($stmtSelect, $stmtUpdate, $stmtInsert) {
            if (str_contains($sql, 'SELECT user_id, expires_at')) {
                return $stmtSelect;
            }
            if (str_contains($sql, 'UPDATE refresh_tokens SET expires_at')) {
                return $stmtUpdate;
            }
            if (str_contains($sql, 'INSERT INTO refresh_tokens')) {
                return $stmtInsert;
            }
            return $this->createMock(PDOStatement::class);
        });

        $auth = new Auth($this->db, $this->cfg);
        $auth->refresh(['refresh_token' => $rt]);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertArrayHasKey('tokens', $body);
        $this->assertNotEmpty($body['tokens']['access_token']);
    }

    public function testRefreshExpiredThrows(): void
    {
        $rt = 'some_refresh_token';

        $stmtSelect = $this->createMock(PDOStatement::class);
        $stmtSelect->method('fetch')->willReturn([
            'user_id' => '42',
            'expires_at' => time() - 10, // expired
        ]);

        $this->db->method('prepare')->willReturn($stmtSelect);

        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(401);

        try {
            $auth->refresh(['refresh_token' => $rt]);
        } finally {
            $this->assertEquals(401, TestHelperRegistry::$lastStatus);
            $this->assertEquals('Geçersiz veya süresi dolmuş yenileme anahtarı.', TestHelperRegistry::$lastBody['error']);
        }
    }
}
