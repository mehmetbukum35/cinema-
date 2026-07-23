<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class TitleCatalogTest extends TestCase
{
    private PDO $db;

    protected function setUp(): void
    {
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->exec(
            'CREATE TABLE titles (
                tmdb_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                locale TEXT NOT NULL,
                title TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                popularity REAL,
                genre_ids TEXT,
                metadata_updated_at INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT \'client\',
                refreshed_at INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (tmdb_id, is_tv, locale)
            )'
        );
    }

    public function testRefreshStaleBatchPromotesClientRows(): void
    {
        $this->db->exec(
            "INSERT INTO titles (tmdb_id, is_tv, locale, title, metadata_updated_at, source, refreshed_at)
             VALUES (1, 0, 'und', 'Draft', 100, 'client', 0)"
        );

        $fake = new class('k') extends Tmdb {
            public function fetchDetails(int $tmdbId, bool $isTv, string $locale): ?array
            {
                return [
                    'title' => 'Backfilled',
                    'overview' => 'Cron',
                    'poster_path' => '/a.jpg',
                    'backdrop_path' => null,
                    'vote_average' => 7.0,
                    'release_date' => '2000-01-01',
                    'popularity' => 1.0,
                    'genre_ids' => '[1]',
                ];
            }
        };

        $catalog = new TitleCatalog($this->db, $fake);
        $count = $catalog->refreshStaleBatch(10, 1_700_000_000_000);
        self::assertSame(1, $count);

        $row = $this->db->query('SELECT * FROM titles WHERE tmdb_id = 1')->fetch(PDO::FETCH_ASSOC);
        self::assertSame('Backfilled', $row['title']);
        self::assertSame('tmdb', $row['source']);
        self::assertSame(1_700_000_000_000, (int) $row['refreshed_at']);
    }

    public function testRefreshStaleBatchNoopWithoutTmdb(): void
    {
        $this->db->exec(
            "INSERT INTO titles (tmdb_id, is_tv, locale, title, source)
             VALUES (2, 0, 'und', 'Draft', 'client')"
        );
        $catalog = new TitleCatalog($this->db, null);
        self::assertSame(0, $catalog->refreshStaleBatch(5));
        $row = $this->db->query('SELECT source FROM titles WHERE tmdb_id = 2')->fetch(PDO::FETCH_ASSOC);
        self::assertSame('client', $row['source']);
    }
}
