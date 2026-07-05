<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/Tmdb.php';

class TmdbTest extends TestCase
{
    private Tmdb $tmdb;

    protected function setUp(): void
    {
        $this->tmdb = new Tmdb('dummy_key');
    }

    public function testFilterResponsePassesNon200Unchanged(): void
    {
        $body = '{"error": "bad request"}';
        $res = $this->tmdb->filterResponse(400, $body);
        $this->assertSame($body, $res);
    }

    public function testFilterResponsePassesSafeMovieDetails(): void
    {
        $body = '{"id":123,"title":"Oppenheimer","adult":false}';
        $res = $this->tmdb->filterResponse(200, $body);
        $this->assertSame($body, $res);
    }

    public function testFilterResponseBlocksAdultMovieDetails(): void
    {
        $body = '{"id":777,"title":"Adult Content","adult":true}';
        
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);
        
        $this->tmdb->filterResponse(200, $body);
    }

    public function testParseRawQueryPreservesDottedTmdbParams(): void
    {
        // PHP $_GET "vote_count.gte" anahtarını "vote_count_gte" yapar; ham
        // parser noktayı korumalı — TMDB filtrelerinin çalışması buna bağlı.
        $params = Tmdb::parseRawQuery(
            'vote_count.gte=100&with_genres=35%7C10402&sort_by=vote_average.desc'
        );
        $this->assertSame('100', $params['vote_count.gte']);
        $this->assertSame('35|10402', $params['with_genres']);
        $this->assertSame('vote_average.desc', $params['sort_by']);
        $this->assertArrayNotHasKey('vote_count_gte', $params);
    }

    public function testParseRawQueryHandlesEdgeCases(): void
    {
        $this->assertSame([], Tmdb::parseRawQuery(''));
        // Değersiz anahtar boş string olur; tekrar eden anahtarda son kazanır.
        $params = Tmdb::parseRawQuery('flag&page=1&page=2');
        $this->assertSame('', $params['flag']);
        $this->assertSame('2', $params['page']);
    }

    public function testParseRawQueryDecodesEncodedCharacters(): void
    {
        $params = Tmdb::parseRawQuery('query=k%C4%B1rm%C4%B1z%C4%B1%20oda');
        $this->assertSame('kırmızı oda', $params['query']);
    }

    public function testFilterResponseFiltersAdultFromLists(): void
    {
        $body = json_encode([
            'page' => 1,
            'results' => [
                ['id' => 101, 'title' => 'Safe Movie 1', 'adult' => false],
                ['id' => 102, 'title' => 'Safe Movie 2'], // adult key missing, should pass
                ['id' => 666, 'title' => 'Naughty Movie', 'adult' => true],
                ['id' => 103, 'title' => 'Safe Movie 3', 'adult' => false],
            ]
        ]);

        $res = $this->tmdb->filterResponse(200, $body);
        $data = json_decode($res, true);

        $this->assertCount(3, $data['results']);
        $this->assertSame(101, $data['results'][0]['id']);
        $this->assertSame(102, $data['results'][1]['id']);
        $this->assertSame(103, $data['results'][2]['id']);
    }
}
