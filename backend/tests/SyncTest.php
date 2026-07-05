<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

class SyncTest extends TestCase
{
    private $db;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = $this->createMock(PDO::class);
    }

    public function testPullFetchesFromAllTablesAndFormatsJson(): void
    {
        $uid = 42;
        $since = 1000;

        // Mock statement that will be reused or separate ones per table
        $stmt = $this->createMock(PDOStatement::class);
        
        // Mock query results for 'ratings' table, others empty
        $stmt->method('fetchAll')->willReturnCallback(function () {
            static $callCount = 0;
            $callCount++;
            if ($callCount === 1) {
                // First table is ratings
                return [
                    [
                        'user_id' => 42,
                        'movie_id' => 101,
                        'is_tv' => 0,
                        'rating' => 3,
                        'genre_ids' => '[28,35]',
                        'title' => 'Test Movie',
                        'updated_at' => 1200,
                        'deleted' => 0,
                    ]
                ];
            }
            return []; // Other tables empty
        });

        $this->db->method('prepare')->willReturn($stmt);

        $sync = new Sync($this->db);
        $sync->pull($uid, $since);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $body = TestHelperRegistry::$lastBody;
        $this->assertArrayHasKey('server_time', $body);
        $this->assertArrayHasKey('ratings', $body);
        $this->assertArrayHasKey('watchlist', $body);
        
        // Check ratings formatting
        $ratings = $body['ratings'];
        $this->assertCount(1, $ratings);
        $this->assertEquals(101, $ratings[0]['movie_id']);
        $this->assertEquals([28, 35], $ratings[0]['genre_ids']); // Should be json decoded
        $this->assertFalse($ratings[0]['deleted']); // Should be converted to boolean
        $this->assertArrayNotHasKey('user_id', $ratings[0]); // Should be unset
    }

    // NOT: push()/upsert() davranışı artık gerçek bir veritabanına karşı
    // SyncIntegrationTest'te (sqlite::memory:) doğrulanıyor — last-write-wins,
    // soft-delete, kullanıcı kapsamı ve push→pull tam tur dahil. Motor-bağımsız
    // upsert kullanıldığı için burada SQL string'i eşleştiren kırılgan mock testi
    // kaldırıldı.

    public function testClearSearchHistoryUpdatesRows(): void
    {
        $uid = 42;
        $stmt = $this->createMock(PDOStatement::class);
        $stmt->method('rowCount')->willReturn(5);

        $this->db->method('prepare')->willReturnCallback(function ($sql) use ($stmt) {
            $this->assertStringContainsString('UPDATE search_history SET deleted = 1', $sql);
            return $stmt;
        });

        $sync = new Sync($this->db);
        $sync->clearSearchHistory($uid);

        $this->assertEquals(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);
        $this->assertEquals(5, TestHelperRegistry::$lastBody['cleared']);
    }
}
