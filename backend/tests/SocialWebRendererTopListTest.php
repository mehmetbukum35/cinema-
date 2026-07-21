<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/SocialWebRenderer.php';

final class SocialWebRendererTopListTest extends TestCase
{
    public function testLoadsSeparatedTopTwentyInUserOrderWithLocaleFallback(): void
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

        $renderer = new SocialWebRenderer($db);
        $method = (new ReflectionClass($renderer))->getMethod('loadTopList');
        $movies = $method->invoke($renderer, 7, false, 'tr');
        $shows = $method->invoke($renderer, 7, true, 'tr');

        $this->assertSame([102, 103, 101], array_map('intval', array_column($movies, 'movie_id')));
        $this->assertSame([1, 2, 3], array_column($movies, 'rank'));
        $this->assertSame('Fallback Film', $movies[1]['title']);
        $this->assertSame('/1b.jpg', $movies[0]['backdrop_path']);
        $this->assertCount(1, $shows);
        $this->assertSame(201, (int) $shows[0]['movie_id']);
    }

    public function testPartitionByMediaSplitsMoviesAndShows(): void
    {
        $renderer = new SocialWebRenderer(new PDO('sqlite::memory:'));
        $method = (new ReflectionClass($renderer))->getMethod('partitionByMedia');
        $items = [
            ['movie_id' => 1, 'is_tv' => 0, 'title' => 'Film'],
            ['movie_id' => 2, 'is_tv' => 1, 'title' => 'Dizi'],
            ['movie_id' => 3, 'is_tv' => 0, 'title' => 'Film 2'],
        ];

        $movies = $method->invoke($renderer, $items, false);
        $shows = $method->invoke($renderer, $items, true);

        $this->assertSame([1, 3], array_map('intval', array_column($movies, 'movie_id')));
        $this->assertSame([2], array_map('intval', array_column($shows, 'movie_id')));
    }
}
