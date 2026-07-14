<?php
declare(strict_types=1);

/**
 * CLI-only FCM smoke test. Run from repo root:
 *   php backend/scripts/test_fcm.php [DEVICE_FCM_TOKEN]
 *
 * Moved from backend/test_fcm.php — not part of the public API surface.
 */

if (php_sapi_name() !== 'cli') {
    exit("This script can only be run from the command line.\n");
}

$backendRoot = dirname(__DIR__);

echo "========================================================\n";
echo "       FIREBASE CLOUD MESSAGING (FCM) TEST ARACI\n";
echo "========================================================\n\n";

$configPath = $backendRoot . '/src/Config.php';
$cfg = file_exists($configPath) ? require $configPath : [];
$defaultSaPath = $cfg['fcm']['service_account'] ?? null;
$projectId = $cfg['fcm']['project_id'] ?? null;

// 1. Service Account Dosyasını Bul
$saPath = null;
$possiblePaths = [];

if ($defaultSaPath) {
    $possiblePaths[] = $defaultSaPath;
}
$possiblePaths[] = $backendRoot . '/src/fcm-service-account.json';
$possiblePaths[] = $backendRoot . '/fcm-service-account.json';
$possiblePaths[] = dirname($backendRoot) . '/fcm-service-account.json';

foreach ($possiblePaths as $path) {
    if (file_exists($path)) {
        $saPath = $path;
        break;
    }
}

if (!$saPath) {
    echo "HATA: Service Account (hizmet hesabı) JSON dosyası bulunamadı!\n";
    echo "Denenebilecek yollar tarandı ancak dosya yok:\n";
    foreach ($possiblePaths as $p) {
        echo " - $p\n";
    }
    echo "\nÇÖZÜM:\n";
    echo "1. Firebase Console > Proje Ayarları > Hizmet Hesapları (Service accounts) bölümüne gidin.\n";
    echo "2. 'Yeni özel anahtar üret' (Generate new private key) butonuna tıklayarak JSON dosyasını indirin.\n";
    echo "3. İndirdiğiniz JSON dosyasını şu isimle projenin içine kaydedin:\n";
    echo "   " . $backendRoot . DIRECTORY_SEPARATOR . "fcm-service-account.json\n\n";
    exit(1);
}

echo "✔ Service Account Dosyası Bulundu: $saPath\n";

// 2. Fcm.php'yi dahil et ve başlat
require_once $backendRoot . '/src/Fcm.php';

try {
    echo "FCM Servisi başlatılıyor...\n";
    $fcm = new Fcm($saPath, $projectId);

    // Yansıtma (Reflection) ile private accessToken metodunu alıp test edelim
    $reflector = new ReflectionClass(Fcm::class);
    $method = $reflector->getMethod('accessToken');
    $method->setAccessible(true);

    echo "Google API ile bağlantı kuruluyor ve OAuth2 Access Token alınıyor...\n";
    $token = $method->invoke($fcm);

    echo "✔ BAŞARILI: Google API kimlik doğrulaması başarılı! Token alındı.\n";
    echo "Token Başlangıcı: " . substr($token, 0, 25) . "...\n\n";

    // Argümanlardan cihaz token'ı kontrol et
    $deviceToken = $argv[1] ?? null;

    if (!$deviceToken) {
        echo "--------------------------------------------------------\n";
        echo "BİLGİ: Cihaz testi için bir FCM token sağlamadınız.\n";
        echo "Gerçek bir cihaza test bildirimi göndermek için komutu şu şekilde çalıştırın:\n";
        echo "php backend/scripts/test_fcm.php <CIHAZ_FCM_TOKENU>\n\n";
        echo "İpucu: Flutter uygulamasını çalıştırdığınızda konsolda\n";
        echo "'🔑 FCM TOKEN: ...' şeklinde yazan değeri kopyalayabilirsiniz.\n";
        echo "--------------------------------------------------------\n";
    } else {
        echo "Cihaza test bildirimi gönderiliyor...\n";
        echo "Hedef Token: $deviceToken\n";

        $success = $fcm->send(
            $deviceToken,
            "Ne İzlesem? Test Bildirimi",
            "FCM bağlantınız başarıyla kuruldu! " . date('H:i:s'),
            [
                'type' => 'friend_request',
                'from_id' => '999',
            ]
        );

        if ($success) {
            echo "✔ BAŞARILI: Bildirim teslim edilmek üzere Firebase'e gönderildi!\n";
            echo "Lütfen cihazınızı kontrol edin.\n";
        } else {
            echo "❌ HATA: Bildirim gönderilemedi. Token geçersiz, süresi geçmiş veya bu projeye ait değil (UNREGISTERED / INVALID_ARGUMENT).\n";
        }
    }

} catch (Exception $e) {
    echo "\n❌ HATA OLUŞTU:\n";
    echo $e->getMessage() . "\n\n";
    echo "Olası Sorunlar:\n";
    echo "1. Google Cloud Console'da 'Firebase Cloud Messaging API' devre dışı bırakılmış olabilir.\n";
    echo "2. Service Account anahtarı silinmiş veya iptal edilmiş olabilir.\n";
    echo "3. Sunucunun saati güncel olmayabilir (JWT imzalama zaman uyumsuzluğu).\n";
    echo "4. İnternet/DNS bağlantı hatası veya cURL/OpenSSL uzantı eksikliği.\n";
}
echo "\n========================================================\n";
