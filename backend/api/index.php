<?php
// Front controller / router. Tüm istekler .htaccess ile buraya gelir.
declare(strict_types=1);

// src/ klasörünün TAM yolu (public_html DIŞINDA tutuluyor).
// Hosting'deki gerçek yola göre AYARLA. cPanel kullanıcı adın foodlabe ise
// ve src'yi /home/mbkmcomt/etc/ altına koyduysan, aşağıdaki doğrudur.
$SRC = '/home/mbkmcomt/etc/src';
if (!is_dir($SRC)) {
    $SRC = dirname(__DIR__) . '/src';
}

require_once "$SRC/Helpers.php";
require_once "$SRC/Db.php";
require_once "$SRC/Jwt.php";
require_once "$SRC/GoogleAuth.php";
require_once "$SRC/AppleAuth.php";
require_once "$SRC/Auth.php";
require_once "$SRC/Sync.php";
require_once "$SRC/Smtp.php";
require_once "$SRC/Fcm.php";
require_once "$SRC/SocialWebRenderer.php";
require_once "$SRC/Social.php";
require_once "$SRC/Moderation.php";
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
$moderation = new Moderation($db, (string) ($cfg['admin_key'] ?? ''));
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
        rate_limit('profile_view', (int) ($cfg['public_profile_rate_limit_per_min'] ?? 60), false);
        $social->renderPublicWebProfile($parts[1]);
        exit;
    }
}

if ($method === 'GET' && (str_starts_with($path, '/download') || str_contains($path, '/download'))) {
    rate_limit('download', (int) ($cfg['download_rate_limit_per_min'] ?? 60), false);
    $social->renderDownloadPage();
    exit;
}

if ($method === 'GET' && str_starts_with($path, '/tmdb/')) {
    // TMDB anahtarı yalnızca sunucuda kalır (bkz. Tmdb.php). Herkese açık ama
    // dakikada IP başına sınırlı — anahtarın kötüye kullanılmasını önler.
    rate_limit('tmdb', (int) ($cfg['tmdb_rate_limit_per_min'] ?? 120), true);
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
        rate_limit('register', (int) $cfg['rate_limit_per_min'], true);
        $auth->register(read_json());
        break;

    case $route === 'POST /auth/verify-email':
        rate_limit('verify_email', (int) $cfg['rate_limit_per_min'], true);
        $auth->verifyEmail(read_json());
        break;

    case $route === 'POST /auth/resend-verification':
        rate_limit('resend_verification', (int) $cfg['rate_limit_per_min'], true);
        $auth->resendVerification(read_json());
        break;

    case $route === 'POST /auth/login':
        rate_limit('login', (int) $cfg['rate_limit_per_min'], true);
        $auth->login(read_json());
        break;

    case $route === 'POST /auth/google':
        rate_limit('google_login', (int) $cfg['rate_limit_per_min'], true);
        $auth->googleLogin(read_json());
        break;

    case $route === 'POST /auth/apple':
        rate_limit('apple_login', (int) $cfg['rate_limit_per_min'], true);
        $auth->appleLogin(read_json());
        break;

    case $route === 'POST /auth/forgot-password':
        rate_limit('forgot_password', (int) $cfg['rate_limit_per_min'], true);
        $auth->forgotPassword(read_json());
        break;

    case $route === 'POST /auth/verify-reset-code':
        rate_limit('verify_reset_code', (int) $cfg['rate_limit_per_min'], true);
        $auth->verifyResetCode(read_json());
        break;

    case $route === 'POST /auth/reset-password':
        rate_limit('reset_password', (int) $cfg['rate_limit_per_min'], true);
        $auth->resetPassword(read_json());
        break;

    // Refresh/logout: kimliksiz uçlar, DoS ve DB yazma florasına karşı IP bazlı
    // sınırlanır. CGNAT arkasındaki meşru kullanıcıları boğmamak için limit
    // login'den daha cömerttir (token yenileme zaten seyrek bir işlemdir).
    case $route === 'POST /auth/refresh':
        rate_limit('refresh', (int) ($cfg['refresh_rate_limit_per_min'] ?? 60), true);
        $auth->refresh(read_json());
        break;

    case $route === 'POST /auth/logout':
        rate_limit('logout', (int) ($cfg['refresh_rate_limit_per_min'] ?? 60), true);
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
        $uid = $auth->requireUser();
        rate_limit('delete_account_u' . $uid, 5, true);
        $auth->deleteAccount($uid);
        break;

    case $route === 'POST /auth/change-password':
        $uid = $auth->requireUser();
        rate_limit('change_password_u' . $uid, (int) ($cfg['rate_limit_per_min'] ?? 20), true);
        $auth->changePassword($uid, read_json());
        break;

    case $route === 'DELETE /auth/google/link':
        $uid = $auth->requireUser();
        rate_limit('unlink_google_u' . $uid, (int) ($cfg['rate_limit_per_min'] ?? 20), true);
        $auth->unlinkGoogle($uid, read_json());
        break;

    // ── Senkronizasyon (ana akış) ──────────────────────────────────────────
    // Kullanıcı bazlı sınır (IP değil): CGNAT arkasındaki farklı kullanıcılar
    // birbirini etkilemez; tek bir hesabın sync'i floodlaması engellenir.
    case $route === 'GET /sync':
        $uid = $auth->requireUser();
        rate_limit('sync_u' . $uid, (int) ($cfg['sync_rate_limit_per_min'] ?? 120), true);
        $sync->pull($uid, (int) ($_GET['since'] ?? 0));
        break;

    case $route === 'POST /sync':
        $uid = $auth->requireUser();
        rate_limit('sync_u' . $uid, (int) ($cfg['sync_rate_limit_per_min'] ?? 120), true);
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

    // Tüm arkadaşların zevk uyumu skorları tek istekte (N+1 HTTP yerine).
    // Tekil /social/match/taste/{id} ucu eski istemciler için korunuyor.
    case $route === 'GET /social/match/taste-all':
        $social->getAllTasteMatches($auth->requireUser());
        break;

    // ── Popüler Listeler (profil beğenileri) ───────────────────────────────
    case $route === 'GET /social/profiles/top':
        $social->getTopProfiles($auth->requireUser());
        break;

    case $route === 'POST /social/profile/like':
        $uid = $auth->requireUser();
        rate_limit('profile_like', (int) $cfg['rate_limit_per_min'], true);
        $social->likeProfile($uid, read_json());
        break;

    // ── Sinema DNA ──────────────────────────────────────────────────────────
    case $route === 'POST /social/dna':
        $uid = $auth->requireUser();
        rate_limit('social_dna', (int) $cfg['rate_limit_per_min'], true);
        $social->publishTasteDna($uid, read_json());
        break;

    // ── Arkadaşa Öneri ──────────────────────────────────────────────────────
    case $route === 'POST /social/recommend':
        $uid = $auth->requireUser();
        rate_limit('recommend', (int) $cfg['rate_limit_per_min'], true);
        $social->recommend($uid, read_json());
        break;

    case $route === 'GET /social/recommendations':
        $social->getRecommendations($auth->requireUser());
        break;

    case $route === 'GET /social/recommendations/sent':
        $social->getSentRecommendations($auth->requireUser());
        break;

    case $route === 'POST /social/recommendations/seen':
        $social->markRecommendationsSeen($auth->requireUser());
        break;

    // ── Yorum Moderasyonu ───────────────────────────────────────────────────
    case $route === 'POST /social/reviews/report':
        $uid = $auth->requireUser();
        rate_limit('report_u' . $uid, (int) $cfg['rate_limit_per_min'], true);
        $social->reportReview($uid, read_json());
        break;

    case $route === 'POST /social/users/block':
        $uid = $auth->requireUser();
        rate_limit('block_u' . $uid, (int) $cfg['rate_limit_per_min'], true);
        $social->blockUser($uid, read_json());
        break;

    case $route === 'POST /social/users/unblock':
        $social->unblockUser($auth->requireUser(), read_json());
        break;

    case $route === 'GET /social/users/blocked':
        $social->getBlockedUsers($auth->requireUser());
        break;

    // Admin paneli: Config'de admin_key boşsa 404 döner (varlığı sızdırılmaz).
    case $route === 'GET /admin/moderation':
        rate_limit('admin_moderation', 30, true);
        $moderation->renderPanel();
        break;

    case $route === 'POST /admin/moderation/action':
        rate_limit('admin_moderation', 30, true);
        $moderation->handleAction();
        break;

    // ── Sağlık kontrolü ────────────────────────────────────────────────────
    case $route === 'GET /health':
        rate_limit('health_check', (int) ($cfg['health_rate_limit_per_min'] ?? 120), false);
        $dbOk = false;
        try {
            $stmt = $db->query("SELECT 1 FROM rate_limits LIMIT 1");
            $dbOk = ($stmt !== false);
        } catch (Throwable $e) {
            $dbOk = false;
        }
        if (!$dbOk) {
            json_out(500, ['ok' => false, 'error' => 'Database or rate_limits table unhealthy']);
        } else {
            json_out(200, ['ok' => true, 'time' => now_ms()]);
        }
        break;

    // ── Migration ucu KALDIRILDI ────────────────────────────────────────────
    // Güvenlik: Migration'ları web üzerinden çalıştırmak production veritabanını
    // tehlikeye atar. Bunun yerine: backend/migrate.php'yi sunucuda CLI ile çalıştırın.
    //   $ php /home/mbkmcomt/etc/../migrate.php
    // case $route === 'GET /run-migrations': kaldırıldı.

    default:
        fail(404, "Bilinmeyen uç: $route");
}
