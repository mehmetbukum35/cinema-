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

    public function __construct(string $apiKey)
    {
        $this->apiKey = $apiKey;
    }

    /**
     * $path:  TMDB API yolu, örn. "/3/discover/movie" (baştaki /tmdb kaldırılmış halde).
     * $query: client'tan gelen query string parametreleri ($_GET). İçinde
     *         api_key varsa yok sayılır; gerçek anahtar burada eklenir.
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

        unset($query['api_key']);
        $query['api_key'] = $this->apiKey;
        $query['include_adult'] = 'false'; // Katman 1: Sunucu düzeyinde adult filtresi zorunluluğu

        $url = self::BASE . $path . '?' . http_build_query($query);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 12,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
        ]);
        $body = curl_exec($ch);
        if ($body === false) {
            curl_close($ch);
            fail(502, 'TMDB sunucusuna ulaşılamadı. Lütfen daha sonra tekrar deneyin.');
        }
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        // Katman 2: Yanıt düzeyinde adult=true filtreleme
        $body = $this->filterResponse($status, $body);

        // TMDB'nin ham cevabını client'a aynen ilet. Bu cevap hiçbir zaman
        // api_key içermez (TMDB kendi yanıtına isteği yansıtmaz), bu yüzden
        // doğrudan geçirmek güvenlidir.
        http_response_code($status > 0 ? $status : 502);
        header('Content-Type: application/json; charset=utf-8');
        echo $body;
        exit;
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
