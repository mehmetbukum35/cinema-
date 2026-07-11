<?php
// ─── GEÇİCİ FCM TEŞHİS ARACI ────────────────────────────────────────────────
// Paylaşımlı hosting'de terminal olmadığı için test_fcm.php'nin web sürümü.
// Kullanım: https://ALANADIN/api/fcm_diag.php?key=ADMIN_KEY
//           (+ isteğe bağlı &token=CIHAZ_FCM_TOKENI ile gerçek test bildirimi)
// ⚠️ İŞİ BİTİNCE BU DOSYAYI SUNUCUDAN SİL!
declare(strict_types=1);
header('Content-Type: text/plain; charset=utf-8');

$SRC = '/home/mbkmcomt/etc/src';
if (!is_dir($SRC)) {
    $SRC = dirname(__DIR__) . '/src';
}

$cfgFile = "$SRC/Config.php";
if (!is_file($cfgFile)) {
    http_response_code(500);
    exit("HATA: Config.php bulunamadı ($cfgFile)\n");
}
$cfg = require $cfgFile;

// Yetki: Config'deki admin_key zorunlu (boşsa araç tamamen kapalı).
$adminKey = (string) ($cfg['admin_key'] ?? '');
$given = (string) ($_GET['key'] ?? '');
if ($adminKey === '' || !hash_equals($adminKey, $given)) {
    http_response_code(403);
    exit("Erişim reddedildi: ?key=ADMIN_KEY parametresi gerekli (Config.php > admin_key).\n");
}

echo "=== FCM TEŞHİS (" . date('Y-m-d H:i:s') . ") ===\n\n";

// [1] Config'deki fcm bloğu
$sa = $cfg['fcm']['service_account'] ?? null;
$pid = $cfg['fcm']['project_id'] ?? null;
echo "[1] Config 'fcm' bloğu: ";
if (empty($sa)) {
    exit("YOK ya da service_account boş.\n    → SONUÇ: Push sunucuda SESSİZCE DEVRE DIŞI. Config.php'ye fcm bloğunu ekleyin.\n");
}
echo "var\n    service_account: $sa\n    project_id: " . ($pid ?: '(boş — JSON içinden okunacak)') . "\n\n";

// [2] Service account dosyası
echo "[2] Service account dosyası: ";
if (!is_file($sa)) {
    exit("BULUNAMADI\n    → Config'deki yol ile dosyanın gerçek yeri farklı. Düzeltin.\n");
}
if (!is_readable($sa)) {
    exit("VAR ama OKUNAMIYOR\n    → Dosya izinlerini kontrol edin (600/640 olmalı, sahibi cPanel kullanıcısı).\n");
}
$json = json_decode((string) file_get_contents($sa), true);
if (!is_array($json) || empty($json['client_email']) || empty($json['private_key'])) {
    exit("VAR ama GEÇERSİZ JSON (client_email/private_key eksik)\n    → Firebase'den yeniden indirin.\n");
}
echo "OK\n    client_email: {$json['client_email']}\n    project_id (JSON): " . ($json['project_id'] ?? '?') . "\n\n";

// [3] Google OAuth2 bağlantısı (Fcm.php'deki gerçek kodla)
require_once "$SRC/Fcm.php";
echo "[3] Google OAuth2 bağlantısı: ";
$fcm = null;
try {
    $fcm = new Fcm($sa, is_string($pid) ? $pid : null);
    $m = (new ReflectionClass(Fcm::class))->getMethod('accessToken');
    $m->setAccessible(true);
    $tok = (string) $m->invoke($fcm);
    echo "OK (access token alındı: " . substr($tok, 0, 12) . "...)\n\n";
} catch (Throwable $e) {
    exit("HATA\n    → " . $e->getMessage() . "\n    → 'bağlantı hatası' görüyorsanız sunucudaki Fcm.php eski olabilir (IPv4 zorlaması ekli son sürümü yükleyin).\n");
}

// [4] Kayıtlı cihaz token'ları (kim push alabilir durumda?)
echo "[4] Kayıtlı cihazlar (device_tokens):\n";
try {
    require_once "$SRC/Db.php";
    $db = Db::conn($cfg);
    $rows = $db->query(
        'SELECT dt.user_id, u.username, dt.platform, COUNT(*) AS n, ' .
        'FROM_UNIXTIME(MAX(dt.updated_at)) AS son_kayit ' .
        'FROM device_tokens dt LEFT JOIN users u ON u.id = dt.user_id ' .
        'GROUP BY dt.user_id, u.username, dt.platform ORDER BY dt.user_id'
    )->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) {
        echo "    HİÇ KAYIT YOK → hiçbir cihaz push token'ı göndermemiş.\n";
        echo "    → Uygulamada oturum açınca token kaydedilir; istemci loglarını kontrol edin.\n";
    } else {
        foreach ($rows as $r) {
            printf(
                "    user #%d (%s) — %s: %d cihaz, son kayıt: %s\n",
                $r['user_id'],
                $r['username'] ?? '?',
                $r['platform'] ?? '?',
                $r['n'],
                $r['son_kayit'] ?? '?'
            );
        }
    }
    echo "\n";
} catch (Throwable $e) {
    echo "    (sorgulanamadı: " . $e->getMessage() . ")\n\n";
}

// [5] İsteğe bağlı: gerçek test bildirimi
$deviceToken = (string) ($_GET['token'] ?? '');
if ($deviceToken !== '') {
    echo "[5] Test bildirimi gönderiliyor (token: " . substr($deviceToken, 0, 16) . "...): ";
    try {
        $ok = $fcm->send(
            $deviceToken,
            'Cinema+ Test Bildirimi',
            'FCM zinciri çalışıyor! ' . date('H:i:s'),
            ['type' => 'friend_request']
        );
        echo $ok
            ? "GÖNDERİLDİ ✓ — cihazı kontrol edin.\n"
            : "REDDEDİLDİ (UNREGISTERED/INVALID) → token bu projeye ait değil ya da süresi geçmiş.\n";
    } catch (Throwable $e) {
        echo "HATA → " . $e->getMessage() . "\n";
    }
} else {
    echo "[5] Test bildirimi: atlandı. Denemek için URL'ye &token=CIHAZ_FCM_TOKENI ekleyin.\n";
}

echo "\n=== BİTTİ — bu dosyayı sunucudan silmeyi unutma! ===\n";
