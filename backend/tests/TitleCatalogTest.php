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

    /** @return array<string, mixed>|false */
    private function row(int $tmdbId): array|false
    {
        return $this->db
            ->query("SELECT * FROM titles WHERE tmdb_id = $tmdbId")
            ->fetch(PDO::FETCH_ASSOC);
    }

    public function testRejectsTraversalInImagePaths(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 10,
            'title' => 'Yol denemesi',
            'poster_path' => '/../../etc/passwd',
            'backdrop_path' => '/valid/path.jpg',
        ], 'movie_id', 100, 'und');

        $row = $this->row(10);
        self::assertNull($row['poster_path']);
        self::assertSame('/valid/path.jpg', $row['backdrop_path']);
    }

    public function testRejectsMalformedImagePaths(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 11,
            'title' => 'Şema denemesi',
            'poster_path' => 'https://evil.example/x.jpg',
        ], 'movie_id', 100, 'und');

        self::assertNull($this->row(11)['poster_path']);
    }

    public function testAnInvalidPathAloneDoesNotCreateARow(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 12,
            'poster_path' => '/../gizli.jpg',
        ], 'movie_id', 100, 'und');

        self::assertFalse($this->row(12));
    }

    public function testClampsNumericFieldsToTheirRange(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 13,
            'title' => 'Sayı denemesi',
            'vote_average' => 9999,
            'popularity' => -5,
        ], 'movie_id', 100, 'und');

        $row = $this->row(13);
        self::assertSame(10.0, (float) $row['vote_average']);
        self::assertSame(0.0, (float) $row['popularity']);
    }

    public function testDropsNonNumericAndNonFiniteNumbers(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 14,
            'title' => 'Çöp sayı',
            'vote_average' => 'sekiz',
            'popularity' => true,
        ], 'movie_id', 100, 'und');

        $row = $this->row(14);
        self::assertNull($row['vote_average']);
        self::assertNull($row['popularity']);
    }

    public function testAcceptsNumbersSentAsStrings(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 15,
            'title' => 'String sayı',
            'vote_average' => '7.5',
        ], 'movie_id', 100, 'und');

        self::assertSame(7.5, (float) $this->row(15)['vote_average']);
    }

    public function testRejectsMalformedReleaseDates(): void
    {
        $catalog = new TitleCatalog($this->db, null);
        $catalog->ingestFromClient([
            'movie_id' => 16,
            'title' => 'Tarih denemesi',
            'release_date' => 'yakında',
        ], 'movie_id', 100, 'und');
        self::assertNull($this->row(16)['release_date']);

        $catalog->ingestFromClient([
            'movie_id' => 17,
            'title' => 'Geçerli tarih',
            'release_date' => '1999-03-31',
        ], 'movie_id', 100, 'und');
        self::assertSame('1999-03-31', $this->row(17)['release_date']);
    }

    public function testApplyTmdbNormalizesTheCanonicalSourceToo(): void
    {
        // Kanonik kaynak da bozuk değer dönebilir; aynı kurallardan geçmeli.
        $catalog = new TitleCatalog($this->db, null);
        $catalog->applyTmdb(18, 0, 'und', [
            'title' => 'Kanonik',
            'poster_path' => '/../kacak.jpg',
            'vote_average' => 42,
            'release_date' => 'bilinmiyor',
        ], 1_700_000_000_000);

        $row = $this->row(18);
        self::assertSame('tmdb', $row['source']);
        self::assertNull($row['poster_path']);
        self::assertSame(10.0, (float) $row['vote_average']);
        self::assertNull($row['release_date']);
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
