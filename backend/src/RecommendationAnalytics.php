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

    public function report(int $days, ?int $nowMs = null): array
    {
        $days = max(1, min(90, $days));
        $nowMs ??= now_ms();
        $since = $nowMs - ($days * 86_400_000);

        $stmt = $this->db->prepare(
            'SELECT impression_id, action, surface, model_version
             FROM recommendation_events
             WHERE created_at >= ?
             ORDER BY created_at ASC'
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
