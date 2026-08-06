<?php
declare(strict_types=1);
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
              WHERE rr.status = 'open'
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
        echo $this->html($key, $open, $hidden, $banned, $recommendations);
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

    /**
     * @param list<array<string, mixed>> $open
     * @param list<array<string, mixed>> $hidden
     * @param list<array<string, mixed>> $banned
     * @param array<string, mixed>|null $recommendations
     */
    private function html(
        string $key,
        array $open,
        array $hidden,
        array $banned,
        ?array $recommendations,
    ): string
    {
        $e = fn($v) => htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
        $keyH = $e($key);
        $actionUrl = $e($this->panelPath() . '/action');

        $card = function (array $r, array $buttons) use ($e, $keyH, $actionUrl): string {
            $name = trim((string) ($r['display_name'] ?? '')) !== ''
                ? $r['display_name'] : '@' . ($r['username'] ?? '?');
            $meta = [];
            if (isset($r['report_count'])) {
                $meta[] = $r['report_count'] . ' şikayet (' . $e($r['reasons'] ?? '') . ')';
            }
            $meta[] = ((int) $r['is_tv'] === 1 ? 'Dizi' : 'Film') . ' #' . (int) $r['movie_id'];
            $btnHtml = '';
            foreach ($buttons as [$action, $label, $cls]) {
                $btnHtml .= '<form method="post" action="' . $actionUrl . '">'
                    . '<input type="hidden" name="csrf" value="' . $keyH . '">'
                    . '<input type="hidden" name="user_id" value="' . (int) $r['reported_user_id'] . '">'
                    . '<input type="hidden" name="movie_id" value="' . (int) $r['movie_id'] . '">'
                    . '<input type="hidden" name="is_tv" value="' . (int) $r['is_tv'] . '">'
                    . '<input type="hidden" name="action" value="' . $e($action) . '">'
                    . '<button class="' . $cls . '">' . $e($label) . '</button></form>';
            }
            return '<div class="card">'
                . '<div class="head"><b>' . $e($name) . '</b> — ' . $e($r['title'] ?? '') . '</div>'
                . '<div class="meta">' . implode(' · ', $meta) . '</div>'
                . '<div class="comment">' . $e($r['comment'] ?? '') . '</div>'
                . '<div class="actions">' . $btnHtml . '</div></div>';
        };

        $openHtml = $open === []
            ? '<p class="empty">Açık şikayet yok. 🎉</p>'
            : implode('', array_map(fn($r) => $card($r, [
                ['hide', 'Gizle', 'danger'],
                ['dismiss', 'Şikayeti Kapat (görünür kalsın)', 'plain'],
                ['ban_user', 'Kullanıcıyı Sustur', 'danger'],
            ]), $open));

        $hiddenHtml = $hidden === []
            ? '<p class="empty">Gizlenmiş yorum yok.</p>'
            : implode('', array_map(fn($r) => $card($r, [
                ['restore', 'Geri Aç', 'ok'],
                ['ban_user', 'Kullanıcıyı Sustur', 'danger'],
            ]), $hidden));

        // Susturulanlar: yalın satır — kullanıcı adı + yasağı kaldır.
        $bannedHtml = $banned === []
            ? '<p class="empty">Susturulmuş kullanıcı yok.</p>'
            : implode('', array_map(function (array $u) use ($e, $keyH, $actionUrl): string {
                $name = trim((string) ($u['display_name'] ?? '')) !== ''
                    ? $u['display_name'] : '@' . ($u['username'] ?? '?');
                return '<div class="card"><div class="head"><b>' . $e($name) . '</b>'
                    . ' <span class="meta">#' . (int) $u['id'] . '</span></div>'
                    . '<div class="meta">Yeni yorumları otomatik gizleniyor. Yasağı kaldırmak eski'
                    . ' yorumları geri açmaz; onları "Gizlenen Yorumlar"dan tek tek geri açın.</div>'
                    . '<div class="actions"><form method="post" action="' . $actionUrl . '">'
                    . '<input type="hidden" name="csrf" value="' . $keyH . '">'
                    . '<input type="hidden" name="user_id" value="' . (int) $u['id'] . '">'
                    . '<input type="hidden" name="action" value="unban_user">'
                    . '<button class="ok">Susturmayı Kaldır</button></form></div></div>';
            }, $banned));

        $recommendationHtml = $this->recommendationHtml($recommendations, $e);

        return '<!doctype html><html lang="tr"><head><meta charset="utf-8">'
            . '<meta name="viewport" content="width=device-width, initial-scale=1">'
            . '<title>Cinema+ Moderasyon</title><style>'
            . 'body{font-family:system-ui,sans-serif;background:#14100c;color:#efe7db;margin:0;padding:24px;max-width:1040px;margin-inline:auto}'
            . 'h1{font-size:22px}h2{font-size:15px;margin-top:32px;color:#c8b99f;text-transform:uppercase;letter-spacing:.08em}'
            . '.intro{color:#b8aa98;font-size:13px;line-height:1.5;margin-top:-6px}'
            . '.card{background:#1f1913;border:1px solid #38302a;border-radius:12px;padding:14px;margin-bottom:12px}'
            . '.head{font-size:14px}.meta{color:#9a8d7c;font-size:12px;margin:4px 0 8px}'
            . '.comment{background:#14100c;border-radius:8px;padding:10px;font-size:13px;line-height:1.4;white-space:pre-wrap;word-break:break-word}'
            . '.actions{display:flex;gap:8px;margin-top:10px}.actions form{margin:0}'
            . 'button{border:0;border-radius:8px;padding:8px 12px;font-size:12px;font-weight:700;cursor:pointer}'
            . 'button:focus-visible{outline:3px solid #f0b44c;outline-offset:2px}'
            . '.danger{background:#a43a2e;color:#fff}.ok{background:#3f7d4e;color:#fff}.plain{background:#38302a;color:#efe7db}'
            . '.empty{color:#9a8d7c}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:14px 0}'
            . '.metric{background:#1f1913;border:1px solid #38302a;border-radius:12px;padding:14px}.metric b{display:block;font-size:22px;color:#f0b44c}'
            . '.metric span{font-size:12px;color:#b8aa98}.table-wrap{overflow-x:auto;border:1px solid #38302a;border-radius:12px}'
            . 'table{width:100%;border-collapse:collapse;min-width:820px;background:#1f1913}th,td{text-align:left;padding:11px 12px;border-bottom:1px solid #38302a;font-size:12px}'
            . 'th{color:#c8b99f;font-size:11px;text-transform:uppercase;letter-spacing:.05em}tbody tr:last-child td{border-bottom:0}'
            . '.rate{font-variant-numeric:tabular-nums;color:#f0b44c}@media(max-width:700px){body{padding:16px}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}'
            . '</style></head><body>'
            . '<h1>Cinema+ Yönetim Paneli</h1>'
            . $recommendationHtml
            . '<h2>Yorum Moderasyonu</h2>'
            . '<h2>Açık Şikayetler (' . count($open) . ')</h2>' . $openHtml
            . '<h2>Gizlenen Yorumlar (' . count($hidden) . ')</h2>' . $hiddenHtml
            . '<h2>Susturulan Kullanıcılar (' . count($banned) . ')</h2>' . $bannedHtml
            . '</body></html>';
    }

    /** @param array<string, mixed>|null $report */
    private function recommendationHtml(?array $report, Closure $e): string
    {
        if ($report === null) {
            return '<h2>Öneri Analizi</h2>'
                . '<p class="empty">Öneri analizi şu anda kullanılamıyor. '
                . '028 migration ve recommendation_events tablosunu kontrol edin.</p>';
        }

        $groups = is_array($report['groups'] ?? null) ? $report['groups'] : [];
        $shown = array_sum(array_column($groups, 'shown'));
        $details = array_sum(array_column($groups, 'detail_opened'));
        $positive = array_sum(array_map(
            static fn(array $row): int =>
                (int) ($row['watchlisted'] ?? 0) + (int) ($row['rated'] ?? 0),
            $groups,
        ));
        $dismissed = array_sum(array_column($groups, 'dismissed'));
        $rate = static fn(int $count): string =>
            $shown === 0 ? '0,0%' : number_format(($count / $shown) * 100, 1, ',', '.') . '%';

        $rows = '';
        foreach ($groups as $row) {
            $rows .= '<tr>'
                . '<td><b>' . $e($row['model_version'] ?? '') . '</b></td>'
                . '<td>' . $e($row['surface'] ?? '') . '</td>'
                . '<td>' . (int) ($row['shown'] ?? 0) . '</td>'
                . '<td>' . (int) ($row['detail_opened'] ?? 0) . '</td>'
                . '<td>' . (int) ($row['trailer_opened'] ?? 0) . '</td>'
                . '<td>' . (int) ($row['watchlisted'] ?? 0) . '</td>'
                . '<td>' . (int) ($row['rated'] ?? 0) . '</td>'
                . '<td>' . (int) ($row['dismissed'] ?? 0) . '</td>'
                . '<td class="rate">' . number_format(
                    ((float) ($row['positive_rate'] ?? 0)) * 100,
                    1,
                    ',',
                    '.',
                ) . '%</td></tr>';
        }
        if ($rows === '') {
            $rows = '<tr><td colspan="9" class="empty">Son 30 günde öneri olayı yok.</td></tr>';
        }

        return '<h2>Öneri Analizi · Son ' . (int) ($report['period_days'] ?? 30) . ' Gün</h2>'
            . '<p class="intro">Kontrol ve kişiselleştirme modellerinin öneri hunisi. '
            . 'Pozitif aksiyon, izleme listesine ekleme ve puanlamanın toplamıdır.</p>'
            . '<div class="metrics">'
            . '<div class="metric"><b>' . $shown . '</b><span>Gösterim</span></div>'
            . '<div class="metric"><b>' . $rate($details) . '</b><span>Detay açılma</span></div>'
            . '<div class="metric"><b>' . $rate($positive) . '</b><span>Pozitif aksiyon</span></div>'
            . '<div class="metric"><b>' . $rate($dismissed) . '</b><span>Reddetme</span></div>'
            . '</div><div class="table-wrap"><table>'
            . '<thead><tr><th>Model</th><th>Yüzey</th><th>Gösterim</th><th>Detay</th>'
            . '<th>Fragman</th><th>Liste</th><th>Puan</th><th>Red</th><th>Pozitif oran</th></tr></thead>'
            . '<tbody>' . $rows . '</tbody></table></div>';
    }
}
