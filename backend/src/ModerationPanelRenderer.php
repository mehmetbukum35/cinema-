<?php
declare(strict_types=1);

class ModerationPanelRenderer
{
    /**
     * @param list<array<string, mixed>> $open
     * @param list<array<string, mixed>> $hidden
     * @param list<array<string, mixed>> $banned
     * @param array<string, mixed>|null $recommendations
     */
    public function render(
        string $csrf,
        string $actionUrl,
        array $open,
        array $hidden,
        array $banned,
        ?array $recommendations,
    ): string
    {
        $e = static fn(mixed $value): string =>
            htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
        $keyH = $e($csrf);
        $actionUrlH = $e($actionUrl);

        $card = function (array $r, array $buttons) use ($e, $keyH, $actionUrlH): string {
            $name = trim((string) ($r['display_name'] ?? '')) !== ''
                ? $r['display_name'] : '@' . ($r['username'] ?? '?');
            $meta = [];
            if (isset($r['report_count'])) {
                $meta[] = $r['report_count'] . ' şikayet (' . $e($r['reasons'] ?? '') . ')';
            }
            $meta[] = ((int) $r['is_tv'] === 1 ? 'Dizi' : 'Film') . ' #' . (int) $r['movie_id'];
            $btnHtml = '';
            foreach ($buttons as [$action, $label, $cls]) {
                $btnHtml .= '<form method="post" action="' . $actionUrlH . '">'
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
            : implode('', array_map(function (array $u) use ($e, $keyH, $actionUrlH): string {
                $name = trim((string) ($u['display_name'] ?? '')) !== ''
                    ? $u['display_name'] : '@' . ($u['username'] ?? '?');
                return '<div class="card"><div class="head"><b>' . $e($name) . '</b>'
                    . ' <span class="meta">#' . (int) $u['id'] . '</span></div>'
                    . '<div class="meta">Yeni yorumları otomatik gizleniyor. Yasağı kaldırmak eski'
                    . ' yorumları geri açmaz; onları "Gizlenen Yorumlar"dan tek tek geri açın.</div>'
                    . '<div class="actions"><form method="post" action="' . $actionUrlH . '">'
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
