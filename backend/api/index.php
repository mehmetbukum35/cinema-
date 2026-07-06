<?php
// Front controller / router. Tüm istekler .htaccess ile buraya gelir.
declare(strict_types=1);

// src/ klasörünün TAM yolu (public_html DIŞINDA tutuluyor).
// Hosting'deki gerçek yola göre AYARLA. cPanel kullanıcı adın foodlabe ise
// ve src'yi /home/foodlabe/etc/ altına koyduysan, aşağıdaki doğrudur.
$SRC = '/home/foodlabe/etc/src';
if (!is_dir($SRC)) {
    $SRC = dirname(__DIR__) . '/src';
}

require_once "$SRC/Helpers.php";
require_once "$SRC/Db.php";
require_once "$SRC/Jwt.php";
require_once "$SRC/Auth.php";
require_once "$SRC/Sync.php";
require_once "$SRC/Smtp.php";
require_once "$SRC/Fcm.php";
require_once "$SRC/SocialWebRenderer.php";
require_once "$SRC/Social.php";
require_once "$SRC/Tmdb.php";

// Config web kök DIŞINDA. Yoksa örnek dosyadan kopyalanmamış demektir.
$cfgFile = "$SRC/Config.php";
if (!is_file($cfgFile)) {
    fail(500, 'Config.php bulunamadı. Config.sample.php dosyasını kopyalayıp doldurun.');
}
$cfg = require $cfgFile;

try {
    $db = Db::conn($cfg);
} catch (Throwable $e) {
    fail(500, 'Veritabanına bağlanılamadı.');
}

$auth = new Auth($db, $cfg);
$sync = new Sync($db);

// FCM yapılandırılmışsa push gönderimini etkinleştir (opsiyonel; yoksa sessizce devre dışı).
$fcm = null;
if (!empty($cfg['fcm']['service_account'])) {
    try {
        $fcm = new Fcm($cfg['fcm']['service_account'], $cfg['fcm']['project_id'] ?? null);
    } catch (Throwable $e) {
        $fcm = null;
    }
}
$social = new Social($db, null, $fcm);
$tmdb = new Tmdb((string) ($cfg['tmdb_api_key'] ?? ''));

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

// Alt klasör ön ekini OTOMATİK algıla: index.php'nin bulunduğu dizini
// (ör. /cinema/api) URL yolundan çıkar. Böylece klasörü nereye koyarsan koy çalışır.
$baseDir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
if ($baseDir !== '' && $baseDir !== '/' && str_starts_with($path, $baseDir)) {
    $path = substr($path, strlen($baseDir));
}
$path = '/' . trim((string) $path, '/');

$route = "$method $path";

// ── Dinamik Yol Çözümleyicileri (Dynamic Routes) ──────────────────────────
if ($method === 'GET' && (str_starts_with($path, '/profile/') || str_contains($path, '/profile/'))) {
    $pos = strpos($path, '/profile/');
    $profilePath = substr($path, $pos);
    $parts = explode('/', trim($profilePath, '/'));
    if (count($parts) === 2 && $parts[0] === 'profile') {
        $social->renderPublicWebProfile($parts[1]);
        exit;
    }
}

if ($method === 'GET' && (str_starts_with($path, '/download') || str_contains($path, '/download'))) {
    $social->renderDownloadPage();
    exit;
}

if ($method === 'GET' && str_starts_with($path, '/tmdb/')) {
    // TMDB anahtarı yalnızca sunucuda kalır (bkz. Tmdb.php). Herkese açık ama
    // dakikada IP başına sınırlı — anahtarın kötüye kullanılmasını önler.
    rate_limit('tmdb', (int) ($cfg['tmdb_rate_limit_per_min'] ?? 120));
    $tmdb->proxy(substr($path, strlen('/tmdb')), $_GET);
    exit;
}

if ($method === 'GET' && str_starts_with($path, '/social/match/watchlist-intersection/')) {
    $parts = explode('/', trim($path, '/'));
    if (count($parts) === 4) {
        $friendId = (int) $parts[3];
        $uid = $auth->requireUser();
        $social->getWatchlistIntersection($uid, $friendId);
        exit;
    }
}

if ($method === 'GET' && str_starts_with($path, '/social/match/taste/')) {
    $parts = explode('/', trim($path, '/'));
    if (count($parts) === 4) {
        $friendId = (int) $parts[3];
        $uid = $auth->requireUser();
        $social->getTasteMatch($uid, $friendId);
        exit;
    }
}

if ($method === 'GET' && str_starts_with($path, '/social/title-reviews/')) {
    $parts = explode('/', trim($path, '/'));
    if (count($parts) === 4) {
        $type = $parts[2];
        $id = (int) $parts[3];
        $uid = $auth->requireUser();
        $social->getTitleReviews($uid, $type, $id);
        exit;
    }
}

// Topluluk skoru: cinema+ üyelerinin bir yapıma verdiği puanların özeti.
// Yol: GET /titles/{movie|tv}/{id}/score  → ['titles', type, id, 'score']
if ($method === 'GET' && str_starts_with($path, '/titles/') && str_ends_with($path, '/score')) {
    $parts = explode('/', trim($path, '/'));
    if (count($parts) === 4 && $parts[3] === 'score') {
        $type = $parts[1];
        $id = (int) $parts[2];
        $uid = $auth->requireUser();
        $social->getTitleScore($uid, $type, $id);
        exit;
    }
}

switch (true) {

    // ── Auth (açık uçlar) ──────────────────────────────────────────────────
    case $route === 'POST /auth/register':
        rate_limit('register', (int) $cfg['rate_limit_per_min']);
        $auth->register(read_json());
        break;

    case $route === 'POST /auth/login':
        rate_limit('login', (int) $cfg['rate_limit_per_min']);
        $auth->login(read_json());
        break;

    case $route === 'POST /auth/forgot-password':
        rate_limit('forgot_password', (int) $cfg['rate_limit_per_min']);
        $auth->forgotPassword(read_json());
        break;

    case $route === 'POST /auth/verify-reset-code':
        rate_limit('verify_reset_code', (int) $cfg['rate_limit_per_min']);
        $auth->verifyResetCode(read_json());
        break;

    case $route === 'POST /auth/reset-password':
        rate_limit('reset_password', (int) $cfg['rate_limit_per_min']);
        $auth->resetPassword(read_json());
        break;

    case $route === 'POST /auth/refresh':
        $auth->refresh(read_json());
        break;

    case $route === 'POST /auth/logout':
        $auth->logout(read_json());
        break;

    // Not: eski "GET /config/tmdb" ucu KALDIRILDI — ham TMDB anahtarını
    // kimliksiz herkese döndürüyordu. Yerine GET /tmdb/* proxy'si geldi
    // (yukarıda, dinamik yol çözümleyicilerde); anahtar artık client'a hiç
    // gönderilmiyor.

    // ── Korumalı uçlar ─────────────────────────────────────────────────────
    case $route === 'GET /me':
        $auth->me($auth->requireUser());
        break;

    case $route === 'DELETE /me':
        $auth->deleteAccount($auth->requireUser());
        break;

    case $route === 'POST /auth/change-password':
        $uid = $auth->requireUser();
        $auth->changePassword($uid, read_json());
        break;

    // ── Senkronizasyon (ana akış) ──────────────────────────────────────────
    case $route === 'GET /sync':
        $uid = $auth->requireUser();
        $sync->pull($uid, (int) ($_GET['since'] ?? 0));
        break;

    case $route === 'POST /sync':
        $uid = $auth->requireUser();
        $sync->push($uid, read_json());
        break;

    // ── Klasik tekil uç örneği (melez) ─────────────────────────────────────
    case $route === 'DELETE /search-history':
        $uid = $auth->requireUser();
        $sync->clearSearchHistory($uid);
        break;

    case $route === 'DELETE /sync':
        $uid = $auth->requireUser();
        $sync->resetAllData($uid);
        break;

    // ── Sosyal Ağ & Arkadaşlık ──────────────────────────────────────────────
    case $route === 'POST /social/profile/setup':
        $social->setupProfile($auth->requireUser(), read_json());
        break;

    case $route === 'GET /social/friends':
        $social->getFriends($auth->requireUser());
        break;

    case $route === 'POST /social/device/register':
        $social->registerDevice($auth->requireUser(), read_json());
        break;

    case $route === 'POST /social/device/unregister':
        $social->unregisterDevice($auth->requireUser(), read_json());
        break;

    case $route === 'POST /social/friends/request':
        $social->sendFriendRequest($auth->requireUser(), read_json());
        break;

    case $route === 'POST /social/friends/accept':
        $social->acceptFriendRequest($auth->requireUser(), read_json());
        break;

    case $route === 'POST /social/friends/reject':
        $social->rejectFriendRequest($auth->requireUser(), read_json());
        break;

    case $route === 'GET /social/friends/activity':
        $friendId = isset($_GET['friend_id']) ? (int) $_GET['friend_id'] : null;
        $social->getActivityFeed($auth->requireUser(), $friendId);
        break;

    case $route === 'GET /social/friends/signals':
        $social->getFriendSignals($auth->requireUser());
        break;

    // ── Sinema DNA ──────────────────────────────────────────────────────────
    case $route === 'POST /social/dna':
        $social->publishTasteDna($auth->requireUser(), read_json());
        break;

    // ── Arkadaşa Öneri ──────────────────────────────────────────────────────
    case $route === 'POST /social/recommend':
        $uid = $auth->requireUser();
        rate_limit('recommend', (int) $cfg['rate_limit_per_min']);
        $social->recommend($uid, read_json());
        break;

    case $route === 'GET /social/recommendations':
        $social->getRecommendations($auth->requireUser());
        break;

    case $route === 'POST /social/recommendations/seen':
        $social->markRecommendationsSeen($auth->requireUser());
        break;

    // ── Sağlık kontrolü ────────────────────────────────────────────────────
    case $route === 'GET /health':
        json_out(200, ['ok' => true, 'time' => now_ms()]);
        break;

    // ── Migration ucu KALDIRILDI ────────────────────────────────────────────
    // Güvenlik: Migration'ları web üzerinden çalıştırmak production veritabanını
    // tehlikeye atar. Bunun yerine: backend/migrate.php'yi sunucuda CLI ile çalıştırın.
    //   $ php /home/foodlabe/etc/../migrate.php
    // case $route === 'GET /run-migrations': kaldırıldı.

    default:
        fail(404, "Bilinmeyen uç: $route");
}
