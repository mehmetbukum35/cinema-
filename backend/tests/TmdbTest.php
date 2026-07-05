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
