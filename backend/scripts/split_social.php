<?php
declare(strict_types=1);

$srcPath = __DIR__ . '/../src/Social.php';
$src = file_get_contents($srcPath);

$chunks = [
    'DevicesTrait' => [
        'start' => '    // ─── POST /social/device/register',
        'end' => '    // ─── POST /social/profile/setup',
    ],
    'ProfilesTrait' => [
        'start' => '    // ─── POST /social/profile/setup',
        'end' => '    // ─── POST /social/friends/request',
    ],
    'FriendsTrait' => [
        'start' => '    // ─── POST /social/friends/request',
        'end' => '    // ─── GET /social/friends/activity',
    ],
    'FeedTrait' => [
        'start' => '    // ─── GET /social/friends/activity',
        'end' => '    // ─── GET /social/match/watchlist-intersection',
    ],
    'MatchTrait' => [
        'start' => '    // ─── GET /social/match/watchlist-intersection',
        'end' => '    // ─── POST /social/recommend',
    ],
    'RecommendationsTrait' => [
        'start' => '    // ─── POST /social/recommend',
        'end' => '    // ─── Yardımcılar (uyum skoru)',
    ],
    'ReviewsTrait' => [
        'start' => '    public function getTitleReviews',
        'end' => '    // ─── POST /social/profile/like',
        'prefix' => "    private const AUTO_HIDE_THRESHOLD = 3;\n    private const REPORT_REASONS = ['profanity', 'spam', 'spoiler', 'harassment', 'other'];\n\n",
    ],
    'ProfilesPublicTrait' => [
        'start' => '    // ─── POST /social/profile/like',
        'end' => '    private function webRenderer(): SocialWebRenderer',
    ],
];

function extractChunk(string $src, string $start, string $end): string
{
    $startPos = strpos($src, $start);
    $endPos = strpos($src, $end, $startPos === false ? 0 : $startPos + strlen($start));
    if ($startPos === false || $endPos === false) {
        throw new RuntimeException("Could not extract between [$start] and [$end]");
    }
    return rtrim(substr($src, $startPos, $endPos - $startPos));
}

$outDir = __DIR__ . '/../src/Social';
if (!is_dir($outDir)) {
    mkdir($outDir, 0777, true);
}

foreach ($chunks as $name => $meta) {
    $body = extractChunk($src, $meta['start'], $meta['end']);
    if (!empty($meta['prefix'])) {
        $body = $meta['prefix'] . $body;
    }
    $content = "<?php\ndeclare(strict_types=1);\n\ntrait Social{$name}\n{\n{$body}\n}\n";
    file_put_contents("$outDir/{$name}.php", $content);
    echo "Wrote {$name}\n";
}

echo "Done.\n";
