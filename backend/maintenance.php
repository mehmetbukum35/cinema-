<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$src = '/home/mbkmcomt/etc/src';
if (!is_dir($src)) {
    $src = __DIR__ . '/src';
}
require_once "$src/Db.php";
require_once "$src/Maintenance.php";
require_once "$src/Tmdb.php";
require_once "$src/TitleCatalog.php";
require_once "$src/Helpers.php";

$configFile = "$src/Config.php";
if (!is_file($configFile)) {
    fwrite(STDERR, "Config.php bulunamadı.\n");
    exit(1);
}

$config = require $configFile;

// Mod: 'cleanup' (günlük temizlik), 'popular' (saatlik Top 20), 'titles'
// (TMDB backfill) ya da 'all' (cleanup+popular+titles — varsayılan).
$mode = $argv[1] ?? 'all';
if (!in_array($mode, ['all', 'cleanup', 'popular', 'titles'], true)) {
    fwrite(STDERR, "Kullanım: maintenance.php [all|cleanup|popular|titles]\n");
    exit(1);
}

$lockName = match ($mode) {
    'popular' => 'cinema-plus-popular.lock',
    'titles' => 'cinema-plus-titles.lock',
    default => 'cinema-plus-maintenance.lock',
};
$lock = fopen(sys_get_temp_dir() . '/' . $lockName, 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    fwrite(STDERR, "Bakım görevi zaten çalışıyor.\n");
    exit(2);
}

try {
    $tmdbKey = (string) ($config['tmdb_api_key'] ?? '');
    $tmdb = $tmdbKey !== '' ? new Tmdb($tmdbKey) : null;
    $maintenance = new Maintenance(Db::conn($config), $config['maintenance'] ?? [], $tmdb);
    $result = match ($mode) {
        'cleanup' => $maintenance->runCleanup(),
        'popular' => $maintenance->runPopular(),
        'titles' => $maintenance->runTitles(),
        default => $maintenance->run(),
    };
    echo json_encode(
        ['ok' => true, 'completed_at' => gmdate(DATE_ATOM), 'affected' => $result],
        JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT
    ) . PHP_EOL;
} catch (Throwable $e) {
    fwrite(STDERR, 'Bakım görevi başarısız: ' . $e->getMessage() . PHP_EOL);
    exit(1);
} finally {
    flock($lock, LOCK_UN);
    fclose($lock);
}
