<?php
declare(strict_types=1);

require_once __DIR__ . '/ModerationPanelRenderer.php';

// Yorum moderasyon paneli: şikayet edilen ve gizlenen yorumları listeler,
// gizle/geri aç/şikayeti kapat aksiyonlarını uygular.
//
// Erişim: Config'deki admin_key, URL'ye yazılmadan POST giriş formunda alınır;
// doğrulama sonrasında HttpOnly/SameSite oturumu ve CSRF belirteci kullanılır.
// Anahtar boşsa panel yok sayılır (404) — varlığı bile sızdırılmaz.
// Panel kasıtlı olarak tek dosyalık, bağımsız bir HTML sayfasıdır: paylaşımlı
// hosting'de ekstra kurulum gerektirmez.

class Moderation
{
    public function __construct(
        private PDO $db,
        private string $adminKey,
        private ?RecommendationAnalytics $recommendationAnalytics = null,
    ) {}

    private function startSession(): void
    {
        if (session_status() !== PHP_SESSION_NONE) return;
        session_name('cinema_moderation');
        session_set_cookie_params([
            'httponly' => true,
            'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
            'samesite' => 'Strict',
            'path' => $this->panelPath(),
        ]);
        session_start();
    }

    private function requireKey(): string
    {
        $this->startSession();
        if (($_SESSION['moderation_admin'] ?? false) === true) {
            $csrf = (string) ($_SESSION['moderation_csrf'] ?? '');
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                $provided = (string) ($_POST['csrf'] ?? '');
                if ($csrf === '' || $provided === '' || !hash_equals($csrf, $provided)) {
                    fail(403, 'Geçersiz istek doğrulaması.');
                }
            }
            return $csrf;
        }

        $key = (string) ($_POST['key'] ?? '');
        if ($key === '' && $_SERVER['REQUEST_METHOD'] === 'GET') {
            $this->renderLogin(false);
        }
        if ($this->adminKey === '') fail(404, 'Bilinmeyen uç.');
        if ($key === '' || !hash_equals($this->adminKey, $key)) {
            $this->renderLogin(true);
        }
        session_regenerate_id(true);
        $_SESSION['moderation_admin'] = true;
        $_SESSION['moderation_csrf'] = bin2hex(random_bytes(24));
        $this->redirectToPanel();
    }

    /**
     * Panelin MUTLAK yolu (alt klasör ön eki dahil), o anki istek yolundan
     * türetilir. Göreli adresler tarayıcıda yanlış çözülüyordu: /action'dan
     * dönen "Location: moderation" yönlendirmesi /admin/moderation/moderation
     * gibi var olmayan bir uca gidiyordu.
     */
    private function panelPath(): string
    {
        $path = (string) (parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH) ?: '');
        $path = rtrim($path, '/');
        if (str_ends_with($path, '/action')) {
            $path = substr($path, 0, -strlen('/action'));
        }
        return $path !== '' ? $path : '/admin/moderation';
    }

    /** İşlem sonrası paneli mutlak yolla yeniden yükler. */
    private function redirectToPanel(): never
    {
        header('Location: ' . $this->panelPath(), true, 303);
        exit;
    }

    private function renderLogin(bool $failed): never
    {
        if ($this->adminKey === '') fail(404, 'Bilinmeyen uç.');
        cinema_send_security_headers('moderation');
        header('Content-Type: text/html; charset=utf-8');
        header('X-Robots-Tag: noindex, nofollow');
        $error = $failed ? '<p style="color:#e86868">Anahtar geçersiz.</p>' : '';
        echo '<!doctype html><html lang="tr"><meta charset="utf-8">'
            . '<meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<title>Cinema+ Moderasyon</title><body style="font-family:system-ui;background:#14100c;color:#efe7db;max-width:420px;margin:10vh auto;padding:24px">'
            . '<h1>Moderasyon Girişi</h1>' . $error
            . '<form method="post" action="' . htmlspecialchars($this->panelPath(), ENT_QUOTES, 'UTF-8') . '">'
            . '<input type="password" name="key" autocomplete="current-password" required style="box-sizing:border-box;width:100%;padding:12px">'
            . '<button style="margin-top:12px;padding:10px 18px">Giriş yap</button></form></body></html>';
        exit;
    }

    // ─── GET /admin/moderation ───────────────────────────────────────────────
    public function renderPanel(): void
    {
        cinema_send_security_headers('moderation');
        $key = $this->requireKey();

        // Açık şikayetler: yorum başına gruplanır, şikayet sayısına göre sıralanır.
        $stOpen = $this->db->prepare(
            "SELECT rr.reported_user_id, rr.movie_id, rr.is_tv,
                    COUNT(DISTINCT rr.reporter_id) AS report_count,
                    GROUP_CONCAT(DISTINCT rr.reason) AS reasons,
                    MAX(rr.created_at) AS last_report_at,
                    r.comment, r.is_hidden, COALESCE(t.title, tf.title) AS title, r.rating,
                    u.username, u.display_name
             FROM review_reports rr
             JOIN ratings r ON r.user_id = rr.reported_user_id
                           AND r.movie_id = rr.movie_id AND r.is_tv = rr.is_tv
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = 'tr'
             LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = 'und'
             JOIN users u ON u.id = rr.reported_user_id
              WHERE rr.status = 'open' AND r.deleted = 0
              GROUP BY rr.reported_user_id, rr.movie_id, rr.is_tv
              ORDER BY report_count DESC, last_report_at DESC
              LIMIT 200"
        );
        $stOpen->execute();
        $open = $stOpen->fetchAll();

        // Gizlenen yorumlar (otomatik filtre veya moderatör kararı): geri açılabilir.
        $stHidden = $this->db->prepare(
            "SELECT r.user_id AS reported_user_id, r.movie_id, r.is_tv,
                    r.comment, COALESCE(t.title, tf.title) AS title, r.rating, r.updated_at,
                    u.username, u.display_name
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = 'tr'
             LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = 'und'
             JOIN users u ON u.id = r.user_id
              WHERE r.is_hidden = 1 AND r.deleted = 0
                AND r.comment IS NOT NULL AND r.comment <> ''
              ORDER BY r.updated_at DESC
              LIMIT 200"
        );
        $stHidden->execute();
        $hidden = $stHidden->fetchAll();

        // Susturulan kullanıcılar: yasağı kaldırma buradan yapılır.
        $stBanned = $this->db->prepare(
            "SELECT id, username, display_name FROM users
              WHERE review_banned = 1 ORDER BY id ASC LIMIT 200"
        );
        $stBanned->execute();
        $banned = $stBanned->fetchAll();

        $recommendations = null;
        if ($this->recommendationAnalytics !== null) {
            try {
                $recommendations = $this->recommendationAnalytics->report(30);
            } catch (Throwable $e) {
                cinema_log('warning', 'Recommendation analytics panel unavailable', [
                    'exception' => get_class($e),
                    'detail' => $e->getMessage(),
                ]);
            }
        }

        header('Content-Type: text/html; charset=utf-8');
        header('X-Robots-Tag: noindex, nofollow');
        $renderer = new ModerationPanelRenderer();
        echo $renderer->render(
            $key,
            $this->panelPath() . '/action',
            $open,
            $hidden,
            $banned,
            $recommendations,
        );
        exit;
    }

    // ─── POST /admin/moderation/action ───────────────────────────────────────
    // Yorum bazlı: hide (gizle + şikayetleri kapat) | restore (geri aç +
    // şikayetleri reddet) | dismiss (görünür bırak, şikayetleri kapat).
    // Kullanıcı bazlı: ban_user (sustur: tüm yorumları gizle + gelecektekiler
    // sync'te otomatik gizlenir + açık şikayetleri kapat) | unban_user
    // (susturmayı kaldır; eski yorumlar gizli kalır, tek tek geri açılır —
    // yasak süresince yazılmış içerik gözden geçirilmeden görünür olmasın).
    public function handleAction(): void
    {
        $key      = $this->requireKey();
        $action   = (string) ($_POST['action'] ?? '');
        $userId   = (int) ($_POST['user_id'] ?? 0);
        $movieId  = (int) ($_POST['movie_id'] ?? 0);
        $isTV     = ((int) ($_POST['is_tv'] ?? 0)) === 1 ? 1 : 0;

        $reviewActions = ['hide', 'restore', 'dismiss'];
        $userActions   = ['ban_user', 'unban_user'];

        if ($userId <= 0 || !in_array($action, array_merge($reviewActions, $userActions), true)) {
            fail(422, 'Geçersiz istek.');
        }

        if (in_array($action, $userActions, true)) {
            $up = $this->db->prepare('UPDATE users SET review_banned = ? WHERE id = ?');
            $up->execute([$action === 'ban_user' ? 1 : 0, $userId]);

            if ($action === 'ban_user') {
                $hideAll = $this->db->prepare(
                    "UPDATE ratings SET is_hidden = 1
                      WHERE user_id = ? AND comment IS NOT NULL AND comment <> ''"
                );
                $hideAll->execute([$userId]);

                $closeReports = $this->db->prepare(
                    "UPDATE review_reports SET status = 'resolved'
                      WHERE reported_user_id = ? AND status = 'open'"
                );
                $closeReports->execute([$userId]);
            }

            $this->redirectToPanel();
        }

        if ($movieId <= 0) {
            fail(422, 'Geçersiz istek.');
        }

        if ($action === 'hide' || $action === 'restore') {
            $up = $this->db->prepare(
                'UPDATE ratings SET is_hidden = ? WHERE user_id = ? AND movie_id = ? AND is_tv = ?'
            );
            $up->execute([$action === 'hide' ? 1 : 0, $userId, $movieId, $isTV]);
        }

        $newStatus = $action === 'restore' ? 'dismissed' : 'resolved';
        $upR = $this->db->prepare(
            "UPDATE review_reports SET status = ?
              WHERE reported_user_id = ? AND movie_id = ? AND is_tv = ? AND status = 'open'"
        );
        $upR->execute([$newStatus, $userId, $movieId, $isTV]);

        $this->redirectToPanel();
    }

}
