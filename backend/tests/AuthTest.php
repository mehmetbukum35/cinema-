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
}
