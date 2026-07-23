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

$configFile = "$src/Config.php";
if (!is_file($configFile)) {
    fwrite(STDERR, "Config.php bulunamadı.\n");
    exit(1);
}

$config = require $configFile;

// Mod: 'cleanup' (günlük temizlik), 'popular' (saatlik Top 20) ya da 'all'
// (ikisi birlikte — varsayılan, geriye dönük uyumlu). İki cron ayrı çağrılabilsin
// diye popüler önhesap kendi lock dosyasını kullanır; böylece saatlik Top 20 ile
// günlük temizlik birbirini bloklamaz.
$mode = $argv[1] ?? 'all';
if (!in_array($mode, ['all', 'cleanup', 'popular'], true)) {
    fwrite(STDERR, "Kullanım: maintenance.php [all|cleanup|popular]\n");
    exit(1);
}

$lockName = $mode === 'popular' ? 'cinema-plus-popular.lock' : 'cinema-plus-maintenance.lock';
$lock = fopen(sys_get_temp_dir() . '/' . $lockName, 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    fwrite(STDERR, "Bakım görevi zaten çalışıyor.\n");
    exit(2);
}

try {
    $maintenance = new Maintenance(Db::conn($config), $config['maintenance'] ?? []);
    $result = match ($mode) {
        'cleanup' => $maintenance->runCleanup(),
        'popular' => $maintenance->runPopular(),
        default   => $maintenance->run(),
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
