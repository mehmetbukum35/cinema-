<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

/**
 * Sync (delta-sync) için GERÇEK veritabanı entegrasyon testleri.
 * PDO mock'u yerine bellek-içi SQLite kullanır; böylece upsert SQL'i
 * sahici bir motorda çalıştırılır ve last-write-wins davranışı doğrulanır.
 * Aynı kod prod'da MySQL/MariaDB üzerinde çalışır (motor-bağımsız upsert).
 */
class SyncIntegrationTest extends TestCase
{
    private PDO $db;
    private Sync $sync;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->createSchema();
        $this->sync = new Sync($this->db);
    }

    // ─── INSERT yolu ────────────────────────────────────────────────────────
    public function testPushInsertsNewRecords(): void
    {
        $this->sync->push(1, [
            'ratings' => [
                ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'genre_ids' => [28, 878],
                 'title' => 'The Matrix', 'updated_at' => 1000],
            ],
            'watchlist' => [
                ['id' => 1399, 'is_tv' => 1, 'title' => 'Game of Thrones',
                 'genre_ids' => [18, 10765], 'updated_at' => 1100],
            ],
        ]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame(2, TestHelperRegistry::$lastBody['applied']);

        $rating = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $rating['rating']);
        $this->assertSame('The Matrix', $rating['title']);
        // JSON kolonu string olarak saklanmalı
        $this->assertSame([28, 878], json_decode($rating['genre_ids'], true));
        // created_at gönderilmediği için updated_at ile doldurulmalı
        $this->assertSame(1000, (int) $rating['created_at']);

        $watch = $this->row('watchlist', 'id', 1399);
        $this->assertSame('Game of Thrones', $watch['title']);
    }

    // ─── last-write-wins: YENİ kazanır ────────────────────────────────────────
    public function testNewerWriteWins(): void
    {
        $this->seedRating(1, 603, 0, 1, 'Old Title', 1000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'title' => 'New Title', 'updated_at' => 2000],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $row['rating']);
        $this->assertSame('New Title', $row['title']);
        $this->assertSame(2000, (int) $row['updated_at']);
    }

    // ─── last-write-wins: ESKİ veri yok sayılır ──────────────────────────────
    public function testStaleWriteIsIgnored(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Current', 2000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 0, 'title' => 'Stale', 'updated_at' => 1000],
        ]);

        // Eski veri uygulanmadı → applied 0
        $this->assertSame(0, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $row['rating']);
        $this->assertSame('Current', $row['title']);
        $this->assertSame(2000, (int) $row['updated_at']);
    }

    // ─── Eşit timestamp da kazanır (>= kuralı) ───────────────────────────────
    public function testEqualTimestampOverwrites(): void
    {
        $this->seedRating(1, 603, 0, 1, 'Before', 1500);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 2, 'title' => 'After', 'updated_at' => 1500],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(2, (int) $row['rating']);
        $this->assertSame('After', $row['title']);
    }

    // ─── Soft delete senkronu ────────────────────────────────────────────────
    public function testSoftDeletePropagates(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Watched', 1000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'updated_at' => 2000, 'deleted' => true],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(1, (int) $row['deleted']);
    }

    // ─── Kullanıcı kapsamı: başka kullanıcının aynı anahtarı etkilenmez ───────
    public function testPushIsScopedToUser(): void
    {
        $this->seedRating(2, 603, 0, 1, 'Bob rating', 1000);

        $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'title' => 'Alice rating', 'updated_at' => 5000],
        ]);

        // Bob'un kaydı dokunulmadan kalmalı
        $bob = $this->rowForUser('ratings', 2, 'movie_id', 603);
        $this->assertSame(1, (int) $bob['rating']);
        $this->assertSame('Bob rating', $bob['title']);
        // Alice için yeni kayıt eklenmeli
        $alice = $this->rowForUser('ratings', 1, 'movie_id', 603);
        $this->assertSame('Alice rating', $alice['title']);
    }

    // ─── Veri kolonu olmayan tablo (watched_seasons) + string anahtar (search) ─
    public function testKeyOnlyAndStringKeyTables(): void
    {
        $applied = 0;
        $this->sync->push(1, [
            'watched_seasons' => [
                ['tv_id' => 1399, 'season_number' => 1, 'updated_at' => 1000],
            ],
            'search_history' => [
                ['query' => 'matrix', 'updated_at' => 1100],
            ],
        ]);
        $applied = TestHelperRegistry::$lastBody['applied'];

        $this->assertSame(2, $applied);
        $this->assertNotNull($this->row('watched_seasons', 'tv_id', 1399));
        $sh = $this->row('search_history', 'query', 'matrix');
        $this->assertSame('matrix', $sh['query']);
        // search_history.created_at otomatik dolmalı
        $this->assertSame(1100, (int) $sh['created_at']);
    }

    // ─── push → pull tam tur (round-trip) ────────────────────────────────────
    public function testPushThenPullRoundTrip(): void
    {
        $this->sync->push(1, [
            'ratings' => [
                ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'genre_ids' => [28, 878],
                 'title' => 'The Matrix', 'updated_at' => 1000],
                ['movie_id' => 604, 'is_tv' => 0, 'rating' => 0, 'title' => 'Deleted One',
                 'updated_at' => 1200, 'deleted' => true],
            ],
        ]);

        TestHelperRegistry::reset();
        $this->sync->pull(1, 0);

        $out = TestHelperRegistry::$lastBody;
        $this->assertArrayHasKey('server_time', $out);
        $this->assertCount(2, $out['ratings']);

        // updated_at artan sırada gelmeli
        $this->assertSame(603, (int) $out['ratings'][0]['movie_id']);
        $this->assertSame(604, (int) $out['ratings'][1]['movie_id']);

        // genre_ids dizi olarak parse edilmeli
        $this->assertSame([28, 878], $out['ratings'][0]['genre_ids']);
        // deleted bool olmalı
        $this->assertIsBool($out['ratings'][1]['deleted']);
        $this->assertTrue($out['ratings'][1]['deleted']);
        // user_id sızdırılmamalı
        $this->assertArrayNotHasKey('user_id', $out['ratings'][0]);
    }

    // ─── pull yalnızca `since`'ten sonrasını döner ───────────────────────────
    public function testPullRespectsSinceCursor(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Old', 1000);
        $this->seedRating(1, 700, 0, 2, 'New', 3000);

        $this->sync->pull(1, 2000);
        $out = TestHelperRegistry::$lastBody;

        $this->assertCount(1, $out['ratings']);
        $this->assertSame(700, (int) $out['ratings'][0]['movie_id']);
    }

    // ───────────────────────── yardımcılar ──────────────────────────────────

    /** Tek tabloyu push edip applied sayısını döndürür. */
    private function push(int $uid, string $table, array $items): int
    {
        TestHelperRegistry::reset();
        $this->sync->push($uid, [$table => $items]);
        return (int) TestHelperRegistry::$lastBody['applied'];
    }

    private function seedRating(int $uid, int $movieId, int $isTv, int $rating, string $title, int $updatedAt): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, created_at, updated_at, deleted)
             VALUES (?, ?, ?, ?, ?, ?, ?, 0)'
        );
        $stmt->execute([$uid, $movieId, $isTv, $rating, $title, $updatedAt, $updatedAt]);
    }

    /** user_id = 1 varsayımıyla tek satır okur. */
    private function row(string $table, string $keyCol, $keyVal): array
    {
        return $this->rowForUser($table, 1, $keyCol, $keyVal);
    }

    private function rowForUser(string $table, int $uid, string $keyCol, $keyVal): array
    {
        $stmt = $this->db->prepare("SELECT * FROM `$table` WHERE user_id = ? AND `$keyCol` = ?");
        $stmt->execute([$uid, $keyVal]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $this->assertIsArray($row, "Beklenen satır bulunamadı: $table.$keyCol=$keyVal");
        return $row;
    }

    private function createSchema(): void
    {
        $this->db->exec(
            'CREATE TABLE ratings (
                user_id INTEGER NOT NULL,
                movie_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                rating INTEGER,
                genre_ids TEXT,
                title TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                popularity REAL,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                comment TEXT,
                is_spoiler INTEGER NOT NULL DEFAULT 0,
                is_private INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, movie_id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE watchlist (
                user_id INTEGER NOT NULL,
                id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                title TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                genre_ids TEXT,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE favorites (
                user_id INTEGER NOT NULL,
                id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                title TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                genre_ids TEXT,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE watched_seasons (
                user_id INTEGER NOT NULL,
                tv_id INTEGER NOT NULL,
                season_number INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, tv_id, season_number)
            )'
        );
        $this->db->exec(
            'CREATE TABLE search_history (
                user_id INTEGER NOT NULL,
                query TEXT NOT NULL,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, query)
            )'
        );
    }
}
