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

    public function testCalibrationEndpointRejectsMissingAdminKey(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);

        (new RecommendationAnalytics($this->db, 'secret'))->renderCalibration(30, 20);
    }

    public function testCalibrationEndpointHiddenWhenAdminKeyUnset(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(404);

        (new RecommendationAnalytics($this->db, ''))->renderCalibration(30, 20);
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

    public function testLikeCurveCountsOnlySwipeAndUsesLatestRating(): void
    {
        // Swipe: raw 0.0 (beğenilmedi) ve raw 1.0 (beğenildi).
        $this->scoredEvent('s1', 'a', 'shown', 'swipe', 'v1', 99_000_000, 0.0);
        $this->scoredEvent('s2', 'a', 'rated', 'swipe', 'v1', 99_000_001, null, 1);
        $this->scoredEvent('s3', 'b', 'shown', 'swipe', 'v1', 99_000_002, 1.0);
        $this->scoredEvent('s4', 'b', 'rated', 'swipe', 'v1', 99_000_003, null, 3);

        // Aynı gösterime ikinci oy: en yenisi kazanır (3 → 0, yani beğeni geri alındı).
        $this->scoredEvent('s5', 'b', 'rated', 'swipe', 'v1', 99_000_009, null, 0);

        // Oylanmamış swipe gösterimi: shown sayılır, rated sayılmaz.
        $this->scoredEvent('s6', 'c', 'shown', 'swipe', 'v1', 99_000_004, 1.0);

        // Browse yüzeyi eğriye HİÇ girmez (ama kuantillere girer).
        $this->scoredEvent('s7', 'd', 'shown', 'browse', 'v1', 99_000_005, 1.0);
        $this->scoredEvent('s8', 'd', 'rated', 'browse', 'v1', 99_000_006, 3);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 4, 100_000_000);

        // Kuantiller browse'u da saydı: 4 gösterim.
        self::assertSame(4, $report['quantiles'][0]['shown']);

        $curve = $report['like_curve'];
        self::assertCount(4, $curve);
        self::assertSame('v1', $curve[0]['model_version']);

        // İlk kova [0.0, 0.25): tek gösterim, oylandı, beğenilmedi.
        self::assertSame(0, $curve[0]['bin']);
        self::assertEqualsWithDelta(0.0, $curve[0]['bin_lo'], 0.001);
        self::assertSame(1, $curve[0]['shown']);
        self::assertSame(1, $curve[0]['rated']);
        self::assertSame(0, $curve[0]['liked']);
        self::assertSame(0.0, $curve[0]['like_rate']);

        // Son kova [0.75, 1.0]: iki gösterim, biri oylandı (en yeni oy 0 → beğeni yok).
        self::assertSame(2, $curve[3]['shown']);
        self::assertSame(1, $curve[3]['rated']);
        self::assertSame(0, $curve[3]['liked']);
    }

    public function testLikeCurveHandlesZeroWidthRange(): void
    {
        // Bir modelin tüm swipe ham skorları aynı: kova genişliği 0.
        $this->scoredEvent('z1', 'a', 'shown', 'swipe', 'v1', 99_000_000, 0.42);
        $this->scoredEvent('z2', 'a', 'rated', 'swipe', 'v1', 99_000_001, null, 3);
        $this->scoredEvent('z3', 'b', 'shown', 'swipe', 'v1', 99_000_002, 0.42);
        $this->scoredEvent('z4', 'b', 'rated', 'swipe', 'v1', 99_000_003, null, 1);
        $this->scoredEvent('z5', 'c', 'shown', 'swipe', 'v1', 99_000_004, 0.42);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 4, 100_000_000);

        $curve = $report['like_curve'];
        self::assertCount(4, $curve);

        // Hepsi ilk kovaya düşer; sınırlar çöker.
        self::assertSame(0, $curve[0]['bin']);
        self::assertSame(0.42, $curve[0]['bin_lo']);
        self::assertSame(0.42, $curve[0]['bin_hi']);
        self::assertSame(3, $curve[0]['shown']);
        self::assertSame(2, $curve[0]['rated']);
        self::assertSame(1, $curve[0]['liked']);
        self::assertSame(0.5, $curve[0]['like_rate']);

        foreach ([1, 2, 3] as $index) {
            self::assertSame(0, $curve[$index]['shown']);
            self::assertSame(0, $curve[$index]['rated']);
            self::assertSame(0, $curve[$index]['liked']);
        }
    }

    public function testNegativeRatingIsNotCountedAsRated(): void
    {
        // "Bunu izlemedim" (-1): gösterim sayılır, oylama sayılmaz.
        $this->scoredEvent('n1', 'a', 'shown', 'swipe', 'v1', 99_000_000, 1.0);
        $this->scoredEvent('n2', 'a', 'rated', 'swipe', 'v1', 99_000_001, null, -1);
        // Beğenilmiş bir gösterime sonradan gelen -1 beğeniyi geri almaz.
        $this->scoredEvent('n3', 'b', 'shown', 'swipe', 'v1', 99_000_002, 1.0);
        $this->scoredEvent('n4', 'b', 'rated', 'swipe', 'v1', 99_000_003, null, 3);
        $this->scoredEvent('n5', 'b', 'rated', 'swipe', 'v1', 99_000_004, null, -1);
        // 0 ("beğenmedim") bir tercih sinyali: oylanmış sayılır.
        $this->scoredEvent('n6', 'c', 'shown', 'swipe', 'v1', 99_000_005, 1.0);
        $this->scoredEvent('n7', 'c', 'rated', 'swipe', 'v1', 99_000_006, null, 0);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 4, 100_000_000);

        $curve = $report['like_curve'];
        self::assertCount(4, $curve);
        self::assertSame(3, $curve[0]['shown']);
        self::assertSame(2, $curve[0]['rated']);
        self::assertSame(1, $curve[0]['liked']);
    }

    public function testLikeCurveIsEmptyWithoutSwipeData(): void
    {
        $this->scoredEvent('b1', 'a', 'shown', 'browse', 'v1', 99_000_000, 0.5);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 20, 100_000_000);

        self::assertSame([], $report['like_curve']);
        self::assertCount(1, $report['quantiles']);
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
