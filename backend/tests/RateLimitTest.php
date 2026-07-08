<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/Db.php';
require_once __DIR__ . '/../src/Helpers.php';

class RateLimitTest extends TestCase
{
    private PDO $db;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        Db::reset();

        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->exec(
            'CREATE TABLE rate_limits (
                ip_bucket TEXT NOT NULL,
                window_time INTEGER NOT NULL,
                request_count INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY (ip_bucket, window_time)
            )'
        );
        Db::inject($this->db);

        $_SERVER['REMOTE_ADDR'] = '127.0.0.1';
    }

    protected function tearDown(): void
    {
        Db::reset();
    }

    public function testLimitExceededReturns429(): void
    {
        rate_limit('test_bucket', 2, true);
        rate_limit('test_bucket', 2, true);

        try {
            rate_limit('test_bucket', 2, true);
            $this->fail('Expected TestExitException for rate limit exceeded');
        } catch (TestExitException $e) {
            $this->assertSame(429, TestHelperRegistry::$lastStatus);
            $this->assertSame(
                'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.',
                TestHelperRegistry::$lastBody['error']
            );
        }
    }

    public function testFailClosedReturns503OnDatabaseError(): void
    {
        Db::reset();
        $broken = $this->createMock(PDO::class);
        $broken->method('getAttribute')->willReturn('sqlite');
        $broken->method('prepare')->willThrowException(new RuntimeException('DB down'));
        Db::inject($broken);

        try {
            rate_limit('broken_bucket', 10, true);
            $this->fail('Expected TestExitException for fail-closed DB error');
        } catch (TestExitException $e) {
            $this->assertSame(503, TestHelperRegistry::$lastStatus);
            $this->assertSame('Geçici hizmet kısıtı.', TestHelperRegistry::$lastBody['error']);
        }
    }

    public function testFailOpenAllowsRequestOnDatabaseError(): void
    {
        Db::reset();
        $broken = $this->createMock(PDO::class);
        $broken->method('getAttribute')->willReturn('sqlite');
        $broken->method('prepare')->willThrowException(new RuntimeException('DB down'));
        Db::inject($broken);

        rate_limit('broken_bucket', 1, false);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
    }
}
