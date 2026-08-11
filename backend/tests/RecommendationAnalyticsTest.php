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
                score_components TEXT NULL,
                metadata TEXT NULL,
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

    public function testCalibrationReportsRawQuantilesAcrossSurfaces(): void
    {
        // v1: 0.0, 0.1, ..., 0.9 — iki farklı yüzeye dağılmış.
        for ($i = 0; $i < 10; $i++) {
            $this->scoredEvent(
                'q' . $i,
                'i' . $i,
                'shown',
                $i % 2 === 0 ? 'browse' : 'swipe',
                'v1',
                99_000_000 + $i,
                $i / 10,
            );
        }
        // Başka kol, tek nokta.
        $this->scoredEvent('q10', 'i10', 'shown', 'browse', 'v2', 99_000_010, 0.5);
        // Gösterim olmayan olay, NULL yük ve bozuk yük sayılmamalı.
        $this->scoredEvent('q11', 'i0', 'rated', 'browse', 'v1', 99_000_011, 5.0);
        $this->event('q12', 'i12', 'shown', 'browse', 'v1', 99_000_012);
        $this->db->exec(
            "INSERT INTO recommendation_events
             (event_id, impression_id, action, surface, model_version,
              score_components, metadata, created_at)
             VALUES ('q13', 'i13', 'shown', 'browse', 'v1', 'json değil', NULL, 99000013),
                    ('q14', 'i14', 'shown', 'browse', 'v1', '{\"genre\":0.4}', NULL, 99000014)"
        );

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 20, 100_000_000);

        self::assertCount(2, $report['quantiles']);

        $v1 = $report['quantiles'][0];
        self::assertSame('v1', $v1['model_version']);
        self::assertSame(10, $v1['shown']);
        self::assertEqualsWithDelta(0.0, $v1['percentiles']['p0'], 0.001);
        self::assertEqualsWithDelta(0.9, $v1['percentiles']['p100'], 0.001);
        self::assertEqualsWithDelta(0.5, $v1['percentiles']['p50'], 0.051);
        self::assertCount(21, $v1['percentiles']);

        $v2 = $report['quantiles'][1];
        self::assertSame(1, $v2['shown']);
        self::assertEqualsWithDelta(0.5, $v2['percentiles']['p0'], 0.001);
        self::assertEqualsWithDelta(0.5, $v2['percentiles']['p100'], 0.001);
    }

    public function testCalibrationClampsPeriodAndBins(): void
    {
        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(365, 1000, 1000);

        self::assertSame(90, $report['period_days']);
        self::assertSame(100, $report['bins']);
        self::assertSame([], $report['quantiles']);
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

    private function scoredEvent(
        string $eventId,
        string $impressionId,
        string $action,
        string $surface,
        string $model,
        int $createdAt,
        ?float $raw = null,
        ?int $rating = null,
    ): void {
        $stmt = $this->db->prepare(
            'INSERT INTO recommendation_events
             (event_id, impression_id, action, surface, model_version,
              score_components, metadata, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $eventId,
            $impressionId,
            $action,
            $surface,
            $model,
            $raw === null ? null : json_encode(['final' => $raw]),
            $rating === null ? null : json_encode(['rating' => $rating]),
            $createdAt,
        ]);
    }
}
