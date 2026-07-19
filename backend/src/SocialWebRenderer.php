<?php
declare(strict_types=1);

require_once __DIR__ . '/TasteDnaWebText.php';

class SocialWebRenderer
{
    public function __construct(private PDO $db) {}

    public function renderPublicWebProfile(string $username): void
    {
        // Sayfa dili: uygulama ?lang=en|tr ile açık seçer; doğrudan tarayıcı
        // ziyaretinde Accept-Language (tr → TR, aksi halde EN).
        $lang = self::resolveWebProfileLang();
        $t = self::webStrings($lang);

        // Kullanıcıyı bul
        $st = $this->db->prepare('SELECT id, display_name, username, is_public, taste_dna FROM users WHERE username = ?');
        $st->execute([$username]);
        $user = $st->fetch();

        if (!$user) {
            $this->renderWebError($t['not_found_title'], $t['not_found_desc']);
            return;
        }

        if ((int) $user['is_public'] !== 1) {
            $this->renderWebError($t['private_title'], $t['private_desc']);
            return;
        }

        $userId = (int) $user['id'];

        // Beğendikleri (Rating = 3 "Harika")
        $stRatings = $this->db->prepare(
            'SELECT r.movie_id, r.is_tv, t.title, t.poster_path, t.vote_average, t.release_date
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv
             WHERE r.user_id = ? AND r.rating = 3 AND r.deleted = 0 AND r.is_private = 0
             ORDER BY r.updated_at DESC
             LIMIT 12'
        );
        $stRatings->execute([$userId]);
        $ratings = $stRatings->fetchAll();

        // İyi Buldukları (Rating = 2 "İyi")
        $stGoodRatings = $this->db->prepare(
            'SELECT r.movie_id, r.is_tv, t.title, t.poster_path, t.vote_average, t.release_date
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv
             WHERE r.user_id = ? AND r.rating = 2 AND r.deleted = 0 AND r.is_private = 0
             ORDER BY r.updated_at DESC
             LIMIT 12'
        );
        $stGoodRatings->execute([$userId]);
        $goodRatings = $stGoodRatings->fetchAll();

        // Watchlist
        $stWatch = $this->db->prepare(
            'SELECT w.id as movie_id, w.is_tv, t.title, t.poster_path, t.vote_average, t.release_date
             FROM watchlist w
             LEFT JOIN titles t ON t.tmdb_id = w.id AND t.is_tv = w.is_tv
             WHERE w.user_id = ? AND w.deleted = 0
             ORDER BY w.created_at DESC
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
            $dna = TasteDnaWebText::build(is_array($decoded) ? $decoded : null, $lang);
        }

        $templatePath = __DIR__ . '/templates/profile.template.php';
        if (is_file($templatePath)) {
            require $templatePath;
        } else {
            $this->renderWebError($t['tmpl_error_title'], $t['tmpl_error_desc']);
        }
        exit;
    }

    /** ?lang= veya Accept-Language ile web profil dili (en|tr). */
    public static function resolveWebProfileLang(): string
    {
        if (isset($_GET['lang'])) {
            $q = (string) $_GET['lang'];
            if ($q === 'en' || $q === 'tr') {
                return $q;
            }
        }
        return self::langFromAcceptLanguage($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '');
    }

    /** Accept-Language: yalnızca tr → Türkçe; diğer tüm durumlar İngilizce. */
    public static function langFromAcceptLanguage(string $header): string
    {
        if ($header === '') {
            return 'en';
        }
        foreach (explode(',', $header) as $part) {
            $tag = strtolower(trim(explode(';', $part)[0]));
            if ($tag === 'tr' || str_starts_with($tag, 'tr-')) {
                return 'tr';
            }
        }
        return 'en';
    }

    /// Web profil sayfasının arayüz metinleri.
    private static function webStrings(string $lang): array
    {
        if ($lang === 'en') {
            return [
                'not_found_title' => 'User not found',
                'not_found_desc'  => 'The profile you are looking for does not seem to exist.',
                'private_title'   => 'Private Profile',
                'private_desc'    => 'This user prefers to keep their profile private.',
                'tmpl_error_title' => 'System Error',
                'tmpl_error_desc'  => 'Profile template not found.',
                'og_title'        => '%s — What Are They Watching? | Cinema+',
                'og_desc'         => "Explore @%s's Cinema DNA and watchlist.",
                'og_dna_title'    => "%s's Cinema DNA: %s",
                'og_dna_desc'     => 'Archetype: %s - %s',
                'cta'             => 'Match & Watch with %s',
                'show_all_themes' => 'Tap to See All',
                'sec_great'       => '🍿 Rated Great',
                'sec_good'        => '👍 Rated Good',
                'sec_watchlist'   => '📝 Watchlist',
                'empty_great'     => 'No titles rated "Great" yet.',
                'empty_good'      => 'No titles rated "Good" yet.',
                'empty_watchlist' => 'Nothing in the watchlist yet.',
                'tv'              => 'TV Show',
                'movie'           => 'Movie',
                'sub_movies'      => '🎬 Movies',
                'sub_tv'          => '📺 TV Shows',
            ];
        }
        return [
            'not_found_title' => 'Kullanıcı bulunamadı',
            'not_found_desc'  => 'Aradığınız profil sistemimizde kayıtlı görünmüyor.',
            'private_title'   => 'Gizli Profil',
            'private_desc'    => 'Bu kullanıcı profilini dış dünyaya kapatmayı tercih etmiş.',
            'tmpl_error_title' => 'Sistem Hatası',
            'tmpl_error_desc'  => 'Profil şablonu bulunamadı.',
            'og_title'        => '%s Neler İzliyor? | Cinema+',
            'og_desc'         => "@%s kullanıcısının Sinema DNA'sını ve izleme listesini keşfet.",
            'og_dna_title'    => "%s Sinema DNA'sı: %s",
            'og_dna_desc'     => 'Arketip: %s - %s',
            'cta'             => '%s ile Eşleş ve İzle',
            'show_all_themes' => 'Tümünü Görmek İçin Dokunun',
            'sec_great'       => '🍿 Harika Buldukları',
            'sec_good'        => '👍 İyi Buldukları',
            'sec_watchlist'   => '📝 İzleme Listesi',
            'empty_great'     => 'Henüz "Harika" olarak puanlanmış bir film veya dizi yok.',
            'empty_good'      => 'Henüz "İyi" olarak puanlanmış bir film veya dizi yok.',
            'empty_watchlist' => 'İzleme listesinde henüz bir şey yok.',
            'tv'              => 'Dizi',
            'movie'           => 'Film',
            'sub_movies'      => '🎬 Filmler',
            'sub_tv'          => '📺 Diziler',
        ];
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
