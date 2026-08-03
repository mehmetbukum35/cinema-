<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class RecommendationAnalyticsTest extends TestCase
{
    private PDO $db;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        unset($_SERVER['HTTP_X_ADMIN_KEY']);
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->exec(
            'CREATE TABLE recommendation_events (
                event_id TEXT PRIMARY KEY,
                impression_id TEXT NOT NULL,
                action TEXT NOT NULL,
                surface TEXT NOT NULL,
                model_version TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )'
        );
    }

    public function testReportBuildsModelAndSurfaceFunnels(): void
    {
        $this->event('1', 'a', 'shown', 'browse', 'v1', 99_000_000);
        $this->event('2', 'a', 'detail_opened', 'browse', 'v1', 99_000_001);
        $this->event('3', 'a', 'watchlisted', 'browse', 'v1', 99_000_002);
        $this->event('3b', 'a', 'trailer_opened', 'movie_detail', 'wrong', 99_000_002);
        $this->event('4', 'b', 'shown', 'browse', 'v1', 99_000_003);
        $this->event('5', 'b', 'dismissed', 'browse', 'v1', 99_000_004);
        $this->event('6', 'c', 'shown', 'swipe', 'v2', 99_000_005);
        $this->event('7', 'c', 'rated', 'swipe', 'v2', 99_000_006);
        $this->event('8', 'old', 'shown', 'browse', 'v0', 1);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->report(1, 100_000_000);

        self::assertCount(2, $report['groups']);
        self::assertSame([
            'model_version' => 'v1',
            'surface' => 'browse',
            'shown' => 2,
            'detail_opened' => 1,
            'trailer_opened' => 1,
            'watchlisted' => 1,
            'rated' => 0,
            'dismissed' => 1,
            'detail_rate' => 0.5,
            'positive_rate' => 0.5,
            'dismiss_rate' => 0.5,
        ], $report['groups'][0]);
        self::assertSame(1.0, $report['groups'][1]['positive_rate']);
    }

    public function testReportClampsPeriodToNinetyDays(): void
    {
        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->report(365, 1000);

        self::assertSame(90, $report['period_days']);
    }

    public function testEndpointRejectsMissingAdminKey(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);

        (new RecommendationAnalytics($this->db, 'secret'))->renderReport(30);
    }

    private function event(
        string $eventId,
        string $impressionId,
        string $action,
        string $surface,
        string $model,
        int $createdAt,
    ): void {
        $stmt = $this->db->prepare(
            'INSERT INTO recommendation_events
             (event_id, impression_id, action, surface, model_version, created_at)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $eventId, $impressionId, $action, $surface, $model, $createdAt,
        ]);
    }
}
