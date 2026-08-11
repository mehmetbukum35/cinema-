<?php
declare(strict_types=1);

final class RecommendationAnalytics
{
    public function __construct(
        private PDO $db,
        private string $adminKey,
    ) {}

    public function renderReport(int $days): void
    {
        $this->requireAdmin();
        json_out(200, $this->report($days));
    }

    public function renderCalibration(int $days, int $bins): void
    {
        $this->requireAdmin();
        json_out(200, $this->calibration($days, $bins));
    }

    /** @return array<string, mixed> */
    public function report(int $days, ?int $nowMs = null): array
    {
        $days = max(1, min(90, $days));
        $nowMs ??= now_ms();
        $since = $nowMs - ($days * 86_400_000);

        $stmt = $this->db->prepare(
            "SELECT e.impression_id, e.action,
                    shown.surface AS surface,
                    shown.model_version AS model_version
             FROM recommendation_events e
             JOIN recommendation_events shown
               ON shown.impression_id = e.impression_id
              AND shown.action = 'shown'
             WHERE shown.created_at >= ?
             ORDER BY shown.created_at ASC, e.created_at ASC"
        );
        $stmt->execute([$since]);

        $groups = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $model = (string) $row['model_version'];
            $surface = (string) $row['surface'];
            $key = $model . "\0" . $surface;
            $groups[$key] ??= [
                'model_version' => $model,
                'surface' => $surface,
                'impressions' => [],
                'actions' => [],
            ];

            $action = (string) $row['action'];
            $groups[$key]['actions'][$action] =
                ($groups[$key]['actions'][$action] ?? 0) + 1;
            if ($action === 'shown') {
                $groups[$key]['impressions'][(string) $row['impression_id']] = true;
            }
        }

        $rows = [];
        foreach ($groups as $group) {
            $shown = count($group['impressions']);
            $actions = $group['actions'];
            $rows[] = [
                'model_version' => $group['model_version'],
                'surface' => $group['surface'],
                'shown' => $shown,
                'detail_opened' => (int) ($actions['detail_opened'] ?? 0),
                'trailer_opened' => (int) ($actions['trailer_opened'] ?? 0),
                'watchlisted' => (int) ($actions['watchlisted'] ?? 0),
                'rated' => (int) ($actions['rated'] ?? 0),
                'dismissed' => (int) ($actions['dismissed'] ?? 0),
                'detail_rate' => $this->rate($actions['detail_opened'] ?? 0, $shown),
                'positive_rate' => $this->rate(
                    ($actions['watchlisted'] ?? 0) + ($actions['rated'] ?? 0),
                    $shown,
                ),
                'dismiss_rate' => $this->rate($actions['dismissed'] ?? 0, $shown),
            ];
        }

        usort($rows, static fn(array $a, array $b): int =>
            [$a['model_version'], $a['surface']]
            <=> [$b['model_version'], $b['surface']]
        );

        return [
            'period_days' => $days,
            'since' => $since,
            'generated_at' => $nowMs,
            'groups' => $rows,
        ];
    }

    private function rate(int $count, int $shown): float
    {
        return $shown === 0 ? 0.0 : round($count / $shown, 4);
    }

    /**
     * Skor kalibrasyonu ölçümü.
     *
     * `quantiles`: TÜM yüzeylerdeki gösterimlerin ham skor dağılımı — rozet her
     * yüzeyde göründüğü için persentil eşlemesinin referansı da yüzey-bağımsız
     * olmalı.
     *
     * @return array<string, mixed>
     */
    public function calibration(int $days, int $bins = 20, ?int $nowMs = null): array
    {
        $days = max(1, min(90, $days));
        $bins = max(4, min(100, $bins));
        $nowMs ??= now_ms();
        $since = $nowMs - ($days * 86_400_000);

        $stmt = $this->db->prepare(
            "SELECT model_version, surface, impression_id, score_components
             FROM recommendation_events
             WHERE action = 'shown' AND created_at >= ?"
        );
        $stmt->execute([$since]);

        // Sabit bellek: ham değerleri saklamayız, 0.001 çözünürlüklü histogram
        // tutarız. 90 günlük tarama satır sayısından bağımsız çalışır.
        $histograms = [];
        // Eğri için yalnız swipe gösterimleri tutulur — payda orada yanlılıksız.
        $swipeRaw = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $raw = $this->rawScore($row['score_components']);
            if ($raw === null) continue;
            $model = (string) $row['model_version'];
            $slot = (int) round($raw * 1000);
            $histograms[$model][$slot] = ($histograms[$model][$slot] ?? 0) + 1;
            if ((string) $row['surface'] === 'swipe') {
                $swipeRaw[(string) $row['impression_id']] = [$model, $raw];
            }
        }

        ksort($histograms);
        $quantiles = [];
        foreach ($histograms as $model => $histogram) {
            $quantiles[] = [
                'model_version' => $model,
                'shown' => array_sum($histogram),
                'percentiles' => $this->percentiles($histogram),
            ];
        }

        $ratedStmt = $this->db->prepare(
            "SELECT impression_id, metadata
             FROM recommendation_events
             WHERE action = 'rated' AND created_at >= ?
             ORDER BY created_at ASC"
        );
        $ratedStmt->execute([$since]);

        // ASC sıra: aynı gösterime gelen ikinci oy birincinin üzerine yazar.
        $likedOf = [];
        while ($row = $ratedStmt->fetch(PDO::FETCH_ASSOC)) {
            $impression = (string) $row['impression_id'];
            if (!isset($swipeRaw[$impression])) continue;
            $rating = $this->ratingOf($row['metadata']);
            if ($rating === null) continue;
            $likedOf[$impression] = $rating >= 2;
        }

        $byModel = [];
        foreach ($swipeRaw as $impression => [$model, $raw]) {
            $byModel[$model][] = [$raw, $likedOf[$impression] ?? null];
        }
        ksort($byModel);

        $likeCurve = [];
        foreach ($byModel as $model => $rows) {
            $values = array_column($rows, 0);
            $lo = min($values);
            $hi = max($values);
            $width = $hi > $lo ? ($hi - $lo) / $bins : 0.0;

            $buckets = array_fill(0, $bins, ['shown' => 0, 'rated' => 0, 'liked' => 0]);
            foreach ($rows as [$raw, $liked]) {
                $index = $width > 0.0
                    ? min($bins - 1, (int) floor(($raw - $lo) / $width))
                    : 0;
                $buckets[$index]['shown']++;
                if ($liked !== null) {
                    $buckets[$index]['rated']++;
                    if ($liked) $buckets[$index]['liked']++;
                }
            }

            foreach ($buckets as $index => $bucket) {
                $likeCurve[] = [
                    'model_version' => $model,
                    'bin' => $index,
                    'bin_lo' => round($lo + ($index * $width), 4),
                    'bin_hi' => round($lo + (($index + 1) * $width), 4),
                    'shown' => $bucket['shown'],
                    'rated' => $bucket['rated'],
                    'liked' => $bucket['liked'],
                    'like_rate' => $this->rate($bucket['liked'], $bucket['rated']),
                ];
            }
        }

        return [
            'period_days' => $days,
            'bins' => $bins,
            'since' => $since,
            'generated_at' => $nowMs,
            'quantiles' => $quantiles,
            'like_curve' => $likeCurve,
        ];
    }

    /** Bozuk/eksik yük sessizce atlanır — rapor tek bir kayıt yüzünden çökmez. */
    private function rawScore(mixed $scoreComponents): ?float
    {
        if (!is_string($scoreComponents) || $scoreComponents === '') return null;
        $decoded = json_decode($scoreComponents, true);
        if (!is_array($decoded) || !isset($decoded['final'])) return null;
        return is_numeric($decoded['final']) ? (float) $decoded['final'] : null;
    }

    /** Bozuk/eksik metadata sessizce atlanır. */
    private function ratingOf(mixed $metadata): ?int
    {
        if (!is_string($metadata) || $metadata === '') return null;
        $decoded = json_decode($metadata, true);
        if (!is_array($decoded) || !isset($decoded['rating'])) return null;
        return is_numeric($decoded['rating']) ? (int) $decoded['rating'] : null;
    }

    /**
     * p0, p5, ..., p100 — histogramdan en yakın-sıra yöntemiyle.
     *
     * @param array<int, int> $histogram slot (raw*1000) => adet
     * @return array<string, float>
     */
    private function percentiles(array $histogram): array
    {
        ksort($histogram);
        $total = array_sum($histogram);
        $slots = array_keys($histogram);

        $targets = [];
        for ($p = 0; $p <= 100; $p += 5) {
            $targets[$p] = (int) ceil($p / 100 * ($total - 1));
        }

        $result = [];
        $index = 0;
        $seen = 0;
        foreach ($targets as $p => $target) {
            while ($seen + $histogram[$slots[$index]] <= $target
                   && $index < count($slots) - 1) {
                $seen += $histogram[$slots[$index]];
                $index++;
            }
            $result['p' . $p] = $slots[$index] / 1000;
        }

        return $result;
    }

    private function requireAdmin(): void
    {
        if ($this->adminKey === '') {
            fail(404, 'Bilinmeyen uç.');
        }
        $provided = (string) ($_SERVER['HTTP_X_ADMIN_KEY'] ?? '');
        if ($provided === '' || !hash_equals($this->adminKey, $provided)) {
            fail(403, 'Yetkisiz erişim.');
        }
    }
}
