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
            'SELECT r.movie_id, r.is_tv, COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = \'und\'
             WHERE r.user_id = ? AND r.rating = 3 AND r.deleted = 0 AND r.is_private = 0
             ORDER BY r.updated_at DESC
             LIMIT 24'
        );
        $stRatings->execute([$lang, $userId]);
        $ratings = $stRatings->fetchAll();

        // İyi Buldukları (Rating = 2 "İyi")
        $stGoodRatings = $this->db->prepare(
            'SELECT r.movie_id, r.is_tv, COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = \'und\'
             WHERE r.user_id = ? AND r.rating = 2 AND r.deleted = 0 AND r.is_private = 0
             ORDER BY r.updated_at DESC
             LIMIT 24'
        );
        $stGoodRatings->execute([$lang, $userId]);
        $goodRatings = $stGoodRatings->fetchAll();

        // Watchlist
        $stWatch = $this->db->prepare(
            'SELECT w.id as movie_id, w.is_tv, COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM watchlist w
             LEFT JOIN titles t ON t.tmdb_id = w.id AND t.is_tv = w.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = w.id AND tf.is_tv = w.is_tv AND tf.locale = \'und\'
             WHERE w.user_id = ? AND w.deleted = 0
             ORDER BY w.created_at DESC
             LIMIT 24'
        );
        $stWatch->execute([$lang, $userId]);
        $watchlist = $stWatch->fetchAll();

        // Kişisel Top 20: favorites.created_at bir zaman damgası değil, kullanıcının
        // açıkça belirlediği 0-tabanlı sırasıdır. Film ve dizi listeleri ayrı tutulur.
        $topMovies = $this->loadTopList($userId, false, $lang);
        $topShows = $this->loadTopList($userId, true, $lang);

        $greatMovies = $this->partitionByMedia($ratings, false);
        $greatShows = $this->partitionByMedia($ratings, true);
        $goodMovies = $this->partitionByMedia($goodRatings, false);
        $goodShows = $this->partitionByMedia($goodRatings, true);
        $watchMovies = $this->partitionByMedia($watchlist, false);
        $watchShows = $this->partitionByMedia($watchlist, true);

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

    /**
     * Split a mixed title list into movies or TV rows.
     *
     * @param array<int, array<string, mixed>> $items
     * @return array<int, array<string, mixed>>
     */
    private function partitionByMedia(array $items, bool $isTv): array
    {
        $out = [];
        foreach ($items as $item) {
            if (((int) ($item['is_tv'] ?? 0) === 1) === $isTv) {
                $out[] = $item;
            }
        }
        return $out;
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
                'brand_kicker'    => 'PUBLIC CINEMA PROFILE',
                'hero_desc'       => 'A personal map of taste, favorites and what comes next.',
                'top_title'       => 'The Definitive Top 20',
                'top_desc'        => 'Hand-picked and ranked — not an algorithmic list.',
                'top_movies'      => 'Top 20 Movies',
                'top_shows'       => 'Top 20 TV Shows',
                'top_empty_movies' => 'No favorite movies ranked yet.',
                'top_empty_shows' => 'No favorite TV shows ranked yet.',
                'dna_kicker'      => 'CINEMA DNA',
                'dna_themes'      => 'Recurring themes',
                'dna_genres'      => 'Dominant genres',
                'sec_great'       => 'Rated Great',
                'sec_good'        => 'Rated Good',
                'sec_watchlist'   => 'Watchlist',
                'empty_great'     => 'No titles rated "Great" yet.',
                'empty_good'      => 'No titles rated "Good" yet.',
                'empty_watchlist' => 'Nothing in the watchlist yet.',
                'empty_great_movies' => 'No movies rated "Great" yet.',
                'empty_great_shows'  => 'No TV shows rated "Great" yet.',
                'empty_good_movies'  => 'No movies rated "Good" yet.',
                'empty_good_shows'   => 'No TV shows rated "Good" yet.',
                'empty_watch_movies' => 'No movies in the watchlist yet.',
                'empty_watch_shows'  => 'No TV shows in the watchlist yet.',
                'tv'              => 'TV Show',
                'movie'           => 'Movie',
                'sub_movies'      => 'Movies',
                'sub_tv'          => 'TV Shows',
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
            'brand_kicker'    => 'HERKESE AÇIK SİNEMA PROFİLİ',
            'hero_desc'       => 'Zevkinin, favorilerinin ve sıradaki keşiflerinin kişisel haritası.',
            'top_title'       => 'Kesin Top 20',
            'top_desc'        => 'Algoritma değil; özenle seçilmiş ve bizzat sıralanmış favoriler.',
            'top_movies'      => 'Top 20 Filmler',
            'top_shows'       => 'Top 20 Diziler',
            'top_empty_movies' => 'Henüz sıralanmış favori film yok.',
            'top_empty_shows' => 'Henüz sıralanmış favori dizi yok.',
            'dna_kicker'      => 'SİNEMA DNA’SI',
            'dna_themes'      => 'Tekrar eden temalar',
            'dna_genres'      => 'Baskın türler',
            'sec_great'       => 'Harika Buldukları',
            'sec_good'        => 'İyi Buldukları',
            'sec_watchlist'   => 'İzleme Listesi',
            'empty_great'     => 'Henüz "Harika" olarak puanlanmış bir film veya dizi yok.',
            'empty_good'      => 'Henüz "İyi" olarak puanlanmış bir film veya dizi yok.',
            'empty_watchlist' => 'İzleme listesinde henüz bir şey yok.',
            'empty_great_movies' => 'Henüz "Harika" film yok.',
            'empty_great_shows'  => 'Henüz "Harika" dizi yok.',
            'empty_good_movies'  => 'Henüz "İyi" film yok.',
            'empty_good_shows'   => 'Henüz "İyi" dizi yok.',
            'empty_watch_movies' => 'İzleme listesinde henüz film yok.',
            'empty_watch_shows'  => 'İzleme listesinde henüz dizi yok.',
            'tv'              => 'Dizi',
            'movie'           => 'Film',
            'sub_movies'      => 'Filmler',
            'sub_tv'          => 'Diziler',
        ];
    }

    /** @return array<int, array<string, mixed>> */
    private function loadTopList(int $userId, bool $isTv, string $lang): array
    {
        $st = $this->db->prepare(
            'SELECT f.id AS movie_id, f.is_tv,
                    COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM favorites f
             LEFT JOIN titles t ON t.tmdb_id = f.id AND t.is_tv = f.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = f.id AND tf.is_tv = f.is_tv AND tf.locale = \'und\'
             WHERE f.user_id = ? AND f.is_tv = ? AND f.deleted = 0
             ORDER BY f.created_at ASC, f.id ASC
             LIMIT 20'
        );
        $st->execute([$lang, $userId, $isTv ? 1 : 0]);
        $rows = $st->fetchAll();
        foreach ($rows as $index => &$row) {
            $row['rank'] = $index + 1;
        }
        unset($row);
        return $rows;
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
