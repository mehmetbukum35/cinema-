<?php
declare(strict_types=1);
// Yorum moderasyon paneli: şikayet edilen ve gizlenen yorumları listeler,
// gizle/geri aç/şikayeti kapat aksiyonlarını uygular.
//
// Erişim: Config'deki 'admin_key' ile (GET /admin/moderation?key=...).
// Anahtar boşsa panel yok sayılır (404) — varlığı bile sızdırılmaz.
// Panel kasıtlı olarak tek dosyalık, bağımsız bir HTML sayfasıdır: paylaşımlı
// hosting'de ekstra kurulum gerektirmez.

class Moderation
{
    public function __construct(private PDO $db, private string $adminKey) {}

    private function requireKey(): string
    {
        $key = (string) ($_GET['key'] ?? $_POST['key'] ?? '');
        if ($this->adminKey === '' || $key === '' || !hash_equals($this->adminKey, $key)) {
            fail(404, 'Bilinmeyen uç.');
        }
        return $key;
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
    private function redirectToPanel(string $key): never
    {
        header('Location: ' . $this->panelPath() . '?key=' . rawurlencode($key), true, 302);
        exit;
    }

    // ─── GET /admin/moderation ───────────────────────────────────────────────
    public function renderPanel(): void
    {
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

        header('Content-Type: text/html; charset=utf-8');
        header('X-Robots-Tag: noindex, nofollow');
        echo $this->html($key, $open, $hidden, $banned);
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

            $this->redirectToPanel($key);
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

        $this->redirectToPanel($key);
    }

    private function html(string $key, array $open, array $hidden, array $banned): string
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
                    . '<input type="hidden" name="key" value="' . $keyH . '">'
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
                    . '<input type="hidden" name="key" value="' . $keyH . '">'
                    . '<input type="hidden" name="user_id" value="' . (int) $u['id'] . '">'
                    . '<input type="hidden" name="action" value="unban_user">'
                    . '<button class="ok">Susturmayı Kaldır</button></form></div></div>';
            }, $banned));

        return '<!doctype html><html lang="tr"><head><meta charset="utf-8">'
            . '<meta name="viewport" content="width=device-width, initial-scale=1">'
            . '<title>Cinema+ Moderasyon</title><style>'
            . 'body{font-family:system-ui,sans-serif;background:#14100c;color:#efe7db;margin:0;padding:24px;max-width:760px;margin-inline:auto}'
            . 'h1{font-size:20px}h2{font-size:15px;margin-top:32px;color:#c8b99f;text-transform:uppercase;letter-spacing:.08em}'
            . '.card{background:#1f1913;border:1px solid #38302a;border-radius:12px;padding:14px;margin-bottom:12px}'
            . '.head{font-size:14px}.meta{color:#9a8d7c;font-size:12px;margin:4px 0 8px}'
            . '.comment{background:#14100c;border-radius:8px;padding:10px;font-size:13px;line-height:1.4;white-space:pre-wrap;word-break:break-word}'
            . '.actions{display:flex;gap:8px;margin-top:10px}.actions form{margin:0}'
            . 'button{border:0;border-radius:8px;padding:8px 12px;font-size:12px;font-weight:700;cursor:pointer}'
            . '.danger{background:#a43a2e;color:#fff}.ok{background:#3f7d4e;color:#fff}.plain{background:#38302a;color:#efe7db}'
            . '.empty{color:#9a8d7c}'
            . '</style></head><body>'
            . '<h1>Cinema+ Yorum Moderasyonu</h1>'
            . '<h2>Açık Şikayetler (' . count($open) . ')</h2>' . $openHtml
            . '<h2>Gizlenen Yorumlar (' . count($hidden) . ')</h2>' . $hiddenHtml
            . '<h2>Susturulan Kullanıcılar (' . count($banned) . ')</h2>' . $bannedHtml
            . '</body></html>';
    }
}
