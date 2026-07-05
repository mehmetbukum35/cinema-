<?php
declare(strict_types=1);

require_once __DIR__ . '/TasteDnaWebText.php';

class SocialWebRenderer
{
    public function __construct(private PDO $db) {}

    public function renderPublicWebProfile(string $username): void
    {
        // Kullanıcıyı bul
        $st = $this->db->prepare('SELECT id, display_name, username, is_public, taste_dna FROM users WHERE username = ?');
        $st->execute([$username]);
        $user = $st->fetch();

        if (!$user) {
            $this->renderWebError('Kullanıcı bulunamadı', 'Aradığınız profil sistemimizde kayıtlı görünmüyor.');
            return;
        }

        if ((int) $user['is_public'] !== 1) {
            $this->renderWebError('Gizli Profil', 'Bu kullanıcı profilini dış dünyaya kapatmayı tercih etmiş.');
            return;
        }

        $userId = (int) $user['id'];

        // Beğendikleri (Rating = 3 "Harika")
        $stRatings = $this->db->prepare(
            'SELECT movie_id, is_tv, title, poster_path, vote_average, release_date
             FROM ratings
             WHERE user_id = ? AND rating = 3 AND deleted = 0
             ORDER BY updated_at DESC
             LIMIT 12'
        );
        $stRatings->execute([$userId]);
        $ratings = $stRatings->fetchAll();

        // Watchlist
        $stWatch = $this->db->prepare(
            'SELECT id as movie_id, is_tv, title, poster_path, vote_average, release_date
             FROM watchlist
             WHERE user_id = ? AND deleted = 0
             ORDER BY created_at DESC
             LIMIT 12'
        );
        $stWatch->execute([$userId]);
        $watchlist = $stWatch->fetchAll();

        $displayName = htmlspecialchars($user['display_name'] ?? $user['username']);
        $userHandle = htmlspecialchars($user['username']);

        // Sinema DNA (snapshot varsa ve hazırsa gösterim dizisi; yoksa null)
        $dna = null;
        if (!empty($user['taste_dna'])) {
            $decoded = json_decode((string) $user['taste_dna'], true);
            $dna = TasteDnaWebText::build(is_array($decoded) ? $decoded : null);
        }

        $templatePath = __DIR__ . '/templates/profile.template.php';
        if (is_file($templatePath)) {
            require $templatePath;
        } else {
            $this->renderWebError('Sistem Hatası', 'Profil şablonu bulunamadı.');
        }
        exit;
    }

    // Yardımcı: Şık Hata Sayfası oluşturucu (Web için)
    private function renderWebError(string $title, string $desc): void
    {
        $templatePath = __DIR__ . '/templates/error.template.php';
        if (is_file($templatePath)) {
            require $templatePath;
        } else {
            echo "<h1>" . htmlspecialchars($title) . "</h1><p>" . htmlspecialchars($desc) . "</p>";
        }
        exit;
    }

    // ─── GET /social/friends/signals ────────────────────────────────────────
    public function renderDownloadPage(): void
    {
        $templatePath = __DIR__ . '/templates/download.template.php';
        if (is_file($templatePath)) {
            require $templatePath;
        } else {
            $this->renderWebError('Sistem Hatası', 'İndirme sayfası şablonu bulunamadı.');
        }
        exit;
    }
}
