<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/Maintenance.php';

final class MaintenanceTest extends TestCase
{
    private PDO $db;
    private int $now = 1_800_000_000_000;

    protected function setUp(): void
    {
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $this->createSchema();
    }

    public function testRunAppliesBoundedRetentionAndKeepsSyncTombstones(): void
    {
        $search = $this->db->prepare(
            'INSERT INTO search_history (user_id, query, updated_at, deleted) VALUES (1, ?, ?, 0)'
        );
        for ($i = 1; $i <= 55; $i++) {
            $search->execute(["query-$i", $this->now - $i]);
        }

        $old = $this->now - 2 * 86400000;
        $this->db->exec(
            "INSERT INTO ratings VALUES
             (1, 10, 0, 'comment', $old, 1),
             (1, 11, 0, 'comment', $old, 0)"
        );
        $this->db->exec("INSERT INTO watchlist VALUES (1, 20, 0, $old, 1)");
        $this->db->exec("INSERT INTO favorites VALUES (1, 30, 0, $old, 1)");

        $staleOpen = $this->now - 25 * 3600000;
        $oldCancelled = $this->now - 8 * 86400000;
        $oldEnded = $this->now - 31 * 86400000;
        $recentEnded = $this->now - 2 * 86400000;
        $this->db->exec(
            "INSERT INTO couch_sessions (status, updated_at) VALUES
             ('active', $staleOpen), ('cancelled', $oldCancelled),
             ('ended', $oldEnded), ('ended', $recentEnded)"
        );

        $nowSeconds = intdiv($this->now, 1000);
        $this->db->exec("INSERT INTO refresh_tokens VALUES (1, " . ($nowSeconds - 1) . "), (2, " . ($nowSeconds + 1) . ")");
        $this->db->exec("INSERT INTO password_resets VALUES ('old', " . ($this->now - 1) . "), ('new', " . ($this->now + 1) . ")");
        $this->db->exec("INSERT INTO email_verifications VALUES ('old', " . ($this->now - 1) . "), ('new', " . ($this->now + 1) . ")");
        $this->db->exec("INSERT INTO rate_limits VALUES ('old', " . ($nowSeconds - 121) . "), ('new', $nowSeconds)");

        $result = (new Maintenance($this->db, ['batch_limit' => 500]))->run($this->now);

        self::assertSame(5, $result['search_history_tombstoned']);
        self::assertSame(50, (int) $this->db->query('SELECT COUNT(*) FROM search_history WHERE deleted = 0')->fetchColumn());
        self::assertSame(55, (int) $this->db->query('SELECT COUNT(*) FROM search_history')->fetchColumn());

        $deletedRating = $this->db->query('SELECT * FROM ratings WHERE movie_id = 10')->fetch();
        self::assertSame(1, (int) $deletedRating['deleted']);
        self::assertSame(2, (int) $this->db->query('SELECT COUNT(*) FROM ratings')->fetchColumn());
        self::assertSame(0, $result['ratings_tombstones_compacted']);
        self::assertSame(0, $result['watchlist_tombstones_compacted']);
        self::assertSame(0, $result['favorites_tombstones_compacted']);

        self::assertSame(1, $result['couch_sessions_expired']);
        self::assertSame(2, $result['couch_sessions_deleted']);
        self::assertSame(2, (int) $this->db->query('SELECT COUNT(*) FROM couch_sessions')->fetchColumn());
        self::assertSame(1, (int) $this->db->query("SELECT COUNT(*) FROM couch_sessions WHERE status = 'cancelled'")->fetchColumn());

        self::assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM refresh_tokens')->fetchColumn());
        self::assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM password_resets')->fetchColumn());
        self::assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM email_verifications')->fetchColumn());
        self::assertSame(1, (int) $this->db->query('SELECT COUNT(*) FROM rate_limits')->fetchColumn());
    }

    public function testBatchLimitBoundsEachCleanupPass(): void
    {
        $seconds = intdiv($this->now, 1000) - 1;
        for ($i = 1; $i <= 5; $i++) {
            $this->db->exec("INSERT INTO refresh_tokens VALUES ($i, $seconds)");
        }

        $result = (new Maintenance($this->db, [
            'batch_limit' => 2,
            'search_history_limit' => 50,
        ]))->run($this->now);

        self::assertSame(2, $result['refresh_tokens_deleted']);
        self::assertSame(3, (int) $this->db->query('SELECT COUNT(*) FROM refresh_tokens')->fetchColumn());
    }

    private function createSchema(): void
    {
        $this->db->exec('CREATE TABLE search_history (user_id INTEGER, query TEXT, updated_at INTEGER, deleted INTEGER, PRIMARY KEY (user_id, query))');
        $this->db->exec('CREATE TABLE ratings (user_id INTEGER, movie_id INTEGER, is_tv INTEGER, comment TEXT, updated_at INTEGER, deleted INTEGER, PRIMARY KEY (user_id, movie_id, is_tv))');
        foreach (['watchlist', 'favorites'] as $table) {
            $this->db->exec("CREATE TABLE $table (user_id INTEGER, id INTEGER, is_tv INTEGER, updated_at INTEGER, deleted INTEGER, PRIMARY KEY (user_id, id, is_tv))");
        }
        $this->db->exec('CREATE TABLE couch_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT, updated_at INTEGER)');
        $this->db->exec('CREATE TABLE refresh_tokens (id INTEGER PRIMARY KEY, expires_at INTEGER)');
        $this->db->exec('CREATE TABLE password_resets (email TEXT PRIMARY KEY, expires_at INTEGER)');
        $this->db->exec('CREATE TABLE email_verifications (email TEXT PRIMARY KEY, expires_at INTEGER)');
        $this->db->exec('CREATE TABLE rate_limits (ip_bucket TEXT, window_time INTEGER, PRIMARY KEY (ip_bucket, window_time))');
    }
}
