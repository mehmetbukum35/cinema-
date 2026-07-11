<?php
declare(strict_types=1);

// Firebase Cloud Messaging — HTTP v1, bağımlılıksız gönderim.
// Service account JSON ile RS256 imzalı bir JWT üretir, OAuth2 access token alır
// ve messages:send ucuna push atar. Access token geçici dosyada (~1 saat) cache'lenir.
// Hiçbir Composer paketi gerektirmez; yalnız openssl + curl (LiteSpeed'de mevcut).
class Fcm
{
    private array $sa;          // service account JSON (decode edilmiş)
    private string $projectId;

    public function __construct(string $serviceAccountPath, ?string $projectId = null)
    {
        $raw = is_file($serviceAccountPath) ? file_get_contents($serviceAccountPath) : false;
        if ($raw === false) {
            throw new RuntimeException('FCM service account dosyası okunamadı.');
        }
        $sa = json_decode($raw, true);
        if (!is_array($sa) || empty($sa['client_email']) || empty($sa['private_key'])) {
            throw new RuntimeException('FCM service account JSON geçersiz.');
        }
        $this->sa = $sa;
        $this->projectId = $projectId ?: (string) ($sa['project_id'] ?? '');
        if ($this->projectId === '') {
            throw new RuntimeException('FCM project_id belirlenemedi.');
        }
    }

    // Tek bir cihaz token'ına gönderir.
    // true: teslim için kabul edildi. false: token geçersiz/kayıtsız (çağıran temizleyebilir).
    public function send(string $deviceToken, string $title, string $body, array $data = []): bool
    {
        $accessToken = $this->accessToken();
        $url = "https://fcm.googleapis.com/v1/projects/{$this->projectId}/messages:send";

        // FCM data alanı yalnız string değer kabul eder.
        $strData = [];
        foreach ($data as $k => $v) {
            $strData[(string) $k] = (string) $v;
        }

        $payload = [
            'message' => [
                'token'        => $deviceToken,
                'notification' => ['title' => $title, 'body' => $body],
                'data'         => $strData,
                'android'      => ['priority' => 'high'],
                'apns'         => ['headers' => ['apns-priority' => '10']],
            ],
        ];

        [$status, $resp] = $this->httpPost($url, json_encode($payload, JSON_UNESCAPED_UNICODE), [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json',
        ]);

        if ($status >= 200 && $status < 300) {
            return true;
        }
        // 400/404 + UNREGISTERED → token artık geçerli değil.
        if ($status === 404 || str_contains($resp, 'UNREGISTERED') || str_contains($resp, 'INVALID_ARGUMENT')) {
            return false;
        }
        // Geçici hata (5xx, ağ vb.) → istisna fırlat ki çağıran token'ı silmesin.
        throw new RuntimeException("FCM gönderimi başarısız (HTTP $status): $resp");
    }

    // Bir kullanıcının tüm cihazlarına gönderir; geçersiz token'ları DB'den temizler.
    // Dönüş: başarıyla gönderilen cihaz sayısı.
    public function sendToUser(PDO $db, int $userId, string $title, string $body, array $data = []): int
    {
        $st = $db->prepare('SELECT token FROM device_tokens WHERE user_id = ?');
        $st->execute([$userId]);
        $tokens = $st->fetchAll(PDO::FETCH_COLUMN);
        if (!$tokens) {
            return 0;
        }

        $sent = 0;
        $stale = [];
        foreach ($tokens as $tok) {
            try {
                if ($this->send($tok, $title, $body, $data)) {
                    $sent++;
                } else {
                    $stale[] = $tok; // geçersiz token
                }
            } catch (Throwable $e) {
                // Geçici hata: token'ı silme, sadece atla.
            }
        }

        if ($stale) {
            $in = implode(',', array_fill(0, count($stale), '?'));
            $db->prepare("DELETE FROM device_tokens WHERE token IN ($in)")->execute($stale);
        }
        return $sent;
    }

    // ─── OAuth2 access token (dosya cache'li) ────────────────────────────────
    private function accessToken(): string
    {
        $cacheFile = sys_get_temp_dir() . '/fcm_token_' . md5($this->sa['client_email']);
        $cached = @json_decode((string) @file_get_contents($cacheFile), true);
        if (is_array($cached) && ($cached['exp'] ?? 0) > time() + 60) {
            return (string) $cached['token'];
        }

        $now = time();
        $jwt = $this->signJwt([
            'iss'   => $this->sa['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud'   => 'https://oauth2.googleapis.com/token',
            'iat'   => $now,
            'exp'   => $now + 3600,
        ]);

        [$status, $resp] = $this->httpPost('https://oauth2.googleapis.com/token', http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]), ['Content-Type: application/x-www-form-urlencoded']);

        $json = json_decode($resp, true);
        if ($status !== 200 || empty($json['access_token'])) {
            throw new RuntimeException("FCM access token alınamadı (HTTP $status): $resp");
        }

        @file_put_contents($cacheFile, json_encode([
            'token' => $json['access_token'],
            'exp'   => $now + (int) ($json['expires_in'] ?? 3600),
        ]), LOCK_EX);

        return (string) $json['access_token'];
    }

    private function signJwt(array $claim): string
    {
        $seg = [
            $this->b64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])),
            $this->b64url(json_encode($claim)),
        ];
        $signingInput = implode('.', $seg);

        $sig = '';
        if (!openssl_sign($signingInput, $sig, $this->sa['private_key'], OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('FCM JWT imzalanamadı (private_key hatalı olabilir).');
        }
        $seg[] = $this->b64url($sig);
        return implode('.', $seg);
    }

    private function b64url(string $d): string
    {
        return rtrim(strtr(base64_encode($d), '+/', '-_'), '=');
    }

    /** @return array{0:int,1:string} [httpStatus, responseBody] */
    private function httpPost(string $url, string $body, array $headers): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 10,
            CURLOPT_CONNECTTIMEOUT => 5,
            // Hosting'de IPv6 çıkışı bozuk: Google API'lerine IPv4 ile bağlan.
            CURLOPT_IPRESOLVE      => CURL_IPRESOLVE_V4,
        ]);
        $resp = curl_exec($ch);
        if ($resp === false) {
            $err = curl_error($ch);
            curl_close($ch);
            throw new RuntimeException('FCM HTTP bağlantı hatası: ' . $err);
        }
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return [$status, (string) $resp];
    }
}
