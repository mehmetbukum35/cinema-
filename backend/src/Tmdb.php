<?php
declare(strict_types=1);

// TMDB (The Movie Database) için sunucu taraflı vekil (reverse proxy).
//
// Neden: Flutter uygulaması eskiden TMDB isteklerini doğrudan kendi yapıp
// api_key'i query string'e ekliyordu. Bu, anahtarın (a) cihaz belleğinde,
// (b) ağ trafiğinde, (c) hata mesajlarında görünmesine yol açıyordu.
// Artık anahtar SADECE bu sunucuda (Config.php) tutulur ve TMDB'ye giden
// isteğe burada eklenir; client'a hiçbir zaman gönderilmez.
//
// Client sadece GET /tmdb/{tmdb_yolu} çağırır (ör. /tmdb/3/discover/movie),
// biz gerçek isteği api.themoviedb.org'a anahtarla birlikte yapıp TMDB'nin
// ham JSON cevabını aynen döneriz.
class Tmdb
{
    private string $apiKey;
    private const BASE = 'https://api.themoviedb.org';

    // SSRF'i önlemek için yalnızca resmi TMDB v3 API yollarına izin ver.
    private const ALLOWED_PREFIX = '/3/';

    public static function cacheTtlForPath(string $path): int
    {
        if (str_contains($path, '/search/')) return 60;
        if (str_contains($path, '/discover/') || str_contains($path, '/trending/')) return 300;
        if (str_contains($path, '/configuration') || str_contains($path, '/genre/')) return 86400;
        return 3600;
    }

    private static function cacheFile(string $path, array $query): string
    {
        $safeQuery = $query;
        unset($safeQuery['api_key']);
        ksort($safeQuery);
        $key = hash('sha256', $path . '?' . http_build_query($safeQuery));
        return sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'cinema_tmdb_' . $key . '.json';
    }

    private static function sendResponse(int $status, string $body, string $cacheState): never
    {
        http_response_code($status > 0 ? $status : 502);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Cinema-Cache: ' . $cacheState);
        echo $body;
        exit;
    }

    public function __construct(string $apiKey)
    {
        $this->apiKey = $apiKey;
    }

    /**
     * PHP, $_GET anahtarlarındaki noktaları alt çizgiye çevirir
     * ("vote_count.gte" → "vote_count_gte"); TMDB ise noktalı adları bekler
     * ve bilinmeyen parametreyi sessizce yok sayar. Bu yüzden query string'i
     * $_GET'e güvenmeden, ham haliyle ve noktaları koruyarak parse ederiz.
     * Aynı anahtar tekrar gelirse son değer kazanır ($_GET davranışıyla aynı).
     */
    public static function parseRawQuery(string $rawQueryString): array
    {
        $params = [];
        foreach (explode('&', $rawQueryString) as $pair) {
            if ($pair === '') {
                continue;
            }
            $eq = strpos($pair, '=');
            if ($eq === false) {
                $params[urldecode($pair)] = '';
                continue;
            }
            $key = urldecode(substr($pair, 0, $eq));
            $params[$key] = urldecode(substr($pair, $eq + 1));
        }
        return $params;
    }

    /**
     * Film/dizi detayını JSON olarak döner (proxy exit etmez). Adult / hata → null.
     * TitleCatalog lazy refresh ve cron backfill için.
     *
     * @return array{
     *   title:?string, overview:?string, poster_path:?string, backdrop_path:?string,
     *   vote_average:?float, release_date:?string, popularity:?float, genre_ids:?string
     * }|null
     */
    public function fetchDetails(int $tmdbId, bool $isTv, string $locale): ?array
    {
        if ($this->apiKey === '' || $tmdbId <= 0) {
            return null;
        }
        $path = $isTv ? "/3/tv/$tmdbId" : "/3/movie/$tmdbId";
        $lang = in_array($locale, ['tr', 'en'], true) ? $locale : 'en';
        $result = $this->request($path, ['language' => $lang]);
        if ($result === null || $result['status'] !== 200 || $result['body'] === '') {
            return null;
        }
        $data = json_decode($result['body'], true);
        if (!is_array($data) || !empty($data['adult'])) {
            return null;
        }

        $title = $data['title'] ?? $data['name'] ?? null;
        $overview = $data['overview'] ?? null;
        $genreIds = null;
        if (isset($data['genres']) && is_array($data['genres'])) {
            $ids = [];
            foreach ($data['genres'] as $genre) {
                if (!is_array($genre)) {
                    continue;
                }
                $id = (int) ($genre['id'] ?? 0);
                if ($id > 0) {
                    $ids[] = $id;
                }
            }
            $genreIds = $ids === [] ? null : json_encode($ids, JSON_UNESCAPED_UNICODE);
        } elseif (isset($data['genre_ids']) && is_array($data['genre_ids'])) {
            $genreIds = json_encode(array_values($data['genre_ids']), JSON_UNESCAPED_UNICODE);
        }

        return [
            'title' => is_string($title) ? $title : null,
            'overview' => is_string($overview) ? $overview : null,
            'poster_path' => isset($data['poster_path']) && is_string($data['poster_path'])
                ? $data['poster_path'] : null,
            'backdrop_path' => isset($data['backdrop_path']) && is_string($data['backdrop_path'])
                ? $data['backdrop_path'] : null,
            'vote_average' => isset($data['vote_average']) ? (float) $data['vote_average'] : null,
            'release_date' => is_string($data['release_date'] ?? null)
                ? $data['release_date']
                : (is_string($data['first_air_date'] ?? null) ? $data['first_air_date'] : null),
            'popularity' => isset($data['popularity']) ? (float) $data['popularity'] : null,
            'genre_ids' => $genreIds,
        ];
    }

    /**
     * $path:  TMDB API yolu, örn. "/3/discover/movie" (baştaki /tmdb kaldırılmış halde).
     * $query: client'tan gelen query string parametreleri. İçinde api_key
     *         varsa yok sayılır; gerçek anahtar burada eklenir. Web isteğinde
     *         noktalı TMDB parametrelerini korumak için $_GET yerine ham
     *         QUERY_STRING kullanılır (bkz. parseRawQuery).
     */
    public function proxy(string $path, array $query): void
    {
        if ($this->apiKey === '') {
            fail(500, 'TMDB proxy sunucuda yapılandırılmamış (tmdb_api_key eksik).');
        }

        $path = '/' . ltrim($path, '/');
        if (!str_starts_with($path, self::ALLOWED_PREFIX)) {
            fail(400, 'Geçersiz TMDB yolu.');
        }

        $rawQs = (string) ($_SERVER['QUERY_STRING'] ?? '');
        if ($rawQs !== '') {
            $query = self::parseRawQuery($rawQs);
        }

        $result = $this->request($path, $query, persistCache: false);
        if ($result === null) {
            fail(502, 'TMDB sunucusuna ulaşılamadı. Lütfen daha sonra tekrar deneyin.');
        }

        // Katman 2: Yanıt düzeyinde adult=true filtreleme (önbelleğe filtrelenmiş yaz).
        $body = $this->filterResponse($result['status'], $result['body']);
        if ($result['status'] === 200 && $body !== '') {
            unset($query['api_key']);
            $query['api_key'] = $this->apiKey;
            $query['include_adult'] = 'false';
            @file_put_contents(self::cacheFile($path, $query), $body, LOCK_EX);
        }

        // TMDB'nin ham cevabını client'a aynen ilet. Bu cevap hiçbir zaman
        // api_key içermez (TMDB kendi yanıtına isteği yansıtmaz), bu yüzden
        // doğrudan geçirmek güvenlidir.
        self::sendResponse($result['status'], $body, $result['cache']);
    }

    /**
     * Ortak HTTP + dosya önbelleği. Exit etmez; curl hatasında null döner.
     *
     * @return array{status:int, body:string, cache:string}|null
     */
    private function request(string $path, array $query, bool $persistCache = true): ?array
    {
        if ($this->apiKey === '') {
            return null;
        }

        $path = '/' . ltrim($path, '/');
        if (!str_starts_with($path, self::ALLOWED_PREFIX)) {
            return null;
        }

        unset($query['api_key']);
        $query['api_key'] = $this->apiKey;
        $query['include_adult'] = 'false'; // Katman 1: Sunucu düzeyinde adult filtresi zorunluluğu

        $url = self::BASE . $path . '?' . http_build_query($query);
        $cacheFile = self::cacheFile($path, $query);
        $ttl = self::cacheTtlForPath($path);
        $cachedBody = is_readable($cacheFile)
            ? (string) @file_get_contents($cacheFile)
            : '';
        $cachedMtime = $cachedBody !== '' ? @filemtime($cacheFile) : false;
        if ($cachedMtime !== false && $cachedMtime + $ttl > time()) {
            return ['status' => 200, 'body' => $cachedBody, 'cache' => 'HIT'];
        }

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 12,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
            // Paylaşımlı hostinglerde IPv6 rotası çoğu zaman kırıktır ve curl
            // önce IPv6 deneyip takılır; TMDB'ye IPv4 ile bağlanmayı zorla.
            CURLOPT_IPRESOLVE      => CURL_IPRESOLVE_V4,
        ]);
        $body = curl_exec($ch);
        if ($body === false) {
            $err = curl_error($ch);
            curl_close($ch);
            cinema_error("TMDB request curl hatası: $err (url: $path)");
            return null;
        }
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($persistCache && $status === 200 && $body !== '') {
            @file_put_contents($cacheFile, $body, LOCK_EX);
        }

        return ['status' => $status, 'body' => (string) $body, 'cache' => 'MISS'];
    }

    public function filterResponse(int $status, string $body): string
    {
        if ($status === 200 && $body !== '') {
            $data = json_decode($body, true);
            if (is_array($data)) {
                // Tekil detayda adult kontrolü
                if ($this->shouldFilterItem($data)) {
                    fail(403, 'Yetişkin içerik bu uygulama üzerinden erişilebilir değildir.');
                }
                
                // Liste sonuçlarında adult filtreleme
                if (isset($data['results']) && is_array($data['results'])) {
                    $filtered = [];
                    foreach ($data['results'] as $item) {
                        if ($this->shouldFilterItem($item)) {
                            continue;
                        }
                        $filtered[] = $item;
                    }
                    $data['results'] = $filtered;
                    return json_encode($data);
                }
            }
        }
        return $body;
    }

    private function shouldFilterItem(array $item): bool
    {
        if (isset($item['adult']) && $item['adult'] === true) {
            return true;
        }
        return false;
    }
}
