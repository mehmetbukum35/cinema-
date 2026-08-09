<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/SocialWebRenderer.php';
require_once __DIR__ . '/../src/SocialWebProfileCatalog.php';

final class SocialWebRendererTopListTest extends TestCase
{
    public function testCatalogLoadsSeparatedTopTwentyInUserOrderWithLocaleFallback(): void
    {
        $db = new PDO('sqlite::memory:');
        $db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $db->exec('CREATE TABLE favorites (user_id INTEGER, id INTEGER, is_tv INTEGER, created_at INTEGER, deleted INTEGER DEFAULT 0)');
        $db->exec('CREATE TABLE titles (tmdb_id INTEGER, is_tv INTEGER, locale TEXT, title TEXT, poster_path TEXT, backdrop_path TEXT, vote_average REAL, release_date TEXT)');
        $db->exec("INSERT INTO favorites VALUES
            (7, 101, 0, 2, 0), (7, 102, 0, 0, 0), (7, 103, 0, 1, 0),
            (7, 201, 1, 0, 0), (7, 999, 0, 3, 1), (8, 888, 0, 0, 0)");
        $db->exec("INSERT INTO titles VALUES
            (101, 0, 'tr', 'Üçüncü Film', '/3.jpg', '/3b.jpg', 8.1, '2003-01-01'),
            (102, 0, 'tr', 'Birinci Film', '/1.jpg', '/1b.jpg', 8.9, '2001-01-01'),
            (103, 0, 'und', 'Fallback Film', '/2.jpg', NULL, 8.4, '2002-01-01'),
            (201, 1, 'tr', 'Birinci Dizi', '/tv.jpg', '/tvb.jpg', 9.0, '2020-01-01')");

        for ($id = 300; $id < 322; $id++) {
            $db->prepare('INSERT INTO favorites VALUES (7, ?, 0, ?, 0)')->execute([$id, $id]);
            $db->prepare("INSERT INTO titles VALUES (?, 0, 'tr', ?, NULL, NULL, 0, NULL)")
                ->execute([$id, 'Film ' . $id]);
        }

        $catalog = new SocialWebProfileCatalog($db);
        $movies = $catalog->loadTopList(7, false, 'tr');
        $shows = $catalog->loadTopList(7, true, 'tr');

        self::assertCount(20, $movies);
        self::assertSame([102, 103, 101], array_map('intval', array_column(array_slice($movies, 0, 3), 'movie_id')));
        self::assertSame(range(1, 20), array_column($movies, 'rank'));
        self::assertSame('Fallback Film', $movies[1]['title']);
        self::assertSame('/1b.jpg', $movies[0]['backdrop_path']);
        self::assertSame([201], array_map('intval', array_column($shows, 'movie_id')));
    }

    public function testSocialDelegatesToWebRenderer(): void
    {
        $db = new PDO('sqlite::memory:');
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $db->exec('CREATE TABLE users (id INTEGER PRIMARY KEY, display_name TEXT, username TEXT, is_public INTEGER, taste_dna TEXT)');

        $db->exec("INSERT INTO users (id, display_name, username, is_public) VALUES (1, 'Mehmet', 'mehmetbukum', 1)");

        $social = new Social($db);
        $this->assertTrue(method_exists($social, 'renderPublicWebProfile'));

        $renderer = $social->webRenderer();
        self::assertInstanceOf(SocialWebRenderer::class, $renderer);
        self::assertSame($renderer, $social->webRenderer());
    }
}
