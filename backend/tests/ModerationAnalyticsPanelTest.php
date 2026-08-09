<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/ModerationPanelRenderer.php';

final class ModerationAnalyticsPanelTest extends TestCase
{
    public function testPanelIncludesRecommendationMetricsAndModelTable(): void
    {
        $renderer = new ModerationPanelRenderer();
        $html = $renderer->render('csrf', '/admin/moderation/action', [], [], [], [
            'period_days' => 30,
            'groups' => [[
                'model_version' => 'recommendation_v4_ab_control',
                'surface' => 'browse',
                'shown' => 10,
                'detail_opened' => 4,
                'trailer_opened' => 2,
                'watchlisted' => 1,
                'rated' => 2,
                'dismissed' => 3,
                'positive_rate' => 0.3,
            ]],
        ]);

        self::assertStringContainsString('Cinema+ Yönetim Paneli', $html);
        self::assertStringContainsString('Öneri Analizi · Son 30 Gün', $html);
        self::assertStringContainsString('recommendation_v4_ab_control', $html);
        self::assertStringContainsString('Pozitif aksiyon', $html);
        self::assertStringContainsString('30,0%', $html);
        self::assertStringContainsString('Yorum Moderasyonu', $html);
    }

    public function testPanelExplainsMissingRecommendationTable(): void
    {
        $html = (new ModerationPanelRenderer())->render(
            'csrf',
            '/admin/moderation/action',
            [],
            [],
            [],
            null,
        );

        self::assertStringContainsString('Öneri analizi şu anda kullanılamıyor', $html);
        self::assertStringContainsString('028 migration', $html);
    }
}
