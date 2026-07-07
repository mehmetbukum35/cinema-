<?php
declare(strict_types=1);

// Google Sign-In ID token doğrulaması.
//
// Doğrulama stratejisi (iki katmanlı):
//   1) YEREL: Google'ın JWKS uçları (https://www.googleapis.com/oauth2/v3/certs)
//      indirilip cache'lenir; ID token'ın RS256 imzası openssl ile YEREL
//      doğrulanır. Ağ turu sadece anahtar yenilemede olur, her giriş için
//      Google'a gidilmez. Kripto için yalnızca PHP'nin dahili openssl'i kullanılır
//      (composer/kütüphane gerekmez → paylaşımlı hosting uyumlu).
//   2) FALLBACK: openssl yoksa ya da JWKS indirilemezse Google'ın tokeninfo ucu
//      (https://oauth2.googleapis.com/tokeninfo) kullanılır.
//
// İmza geçerli olduktan sonra biz yalnızca claim'leri (aud/iss/exp/email_verified)
// kontrol ederiz. Karar mantığı [validateClaims] içinde saf ve test edilebilirdir.
class GoogleAuth
{
    private const TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo?id_token=';
    private const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
    private const VALID_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
    // Google anahtarları günlerce geçerli; 6 saatlik cache güvenli ve azdır.
    private const JWKS_CACHE_TTL = 21600;

    /**
     * ID token'ı doğrulayıp claim'leri döner; geçersizse null.
     * $clientIds: kabul edilen OAuth client ID'leri (aud bunlardan biri olmalı).
     */
    public static function verifyIdToken(string $idToken, array $clientIds): ?array
    {
        // 1) Yerel JWKS/RS256 doğrulaması.
        $local = self::verifyWithJwks($idToken);
        if ($local['status'] === 'ok') {
            return self::validateClaims($local['claims'], $clientIds) ? $local['claims'] : null;
        }
        // İmza/anahtar kesin geçersizse fallback'e düşmeyiz (güvenlik bypass'ı olmaz).
        if ($local['status'] === 'reject') {
            return null;
        }

        // 2) 'unavailable' → openssl yok ya da JWKS indirilemedi → tokeninfo fallback.
        $claims = self::fetchTokenInfo($idToken);
        if ($claims === null) {
            return null;
        }
        return self::validateClaims($claims, $clientIds) ? $claims : null;
    }

    /**
     * Saf claim doğrulaması (ağ yok) — birim testlerin hedefi.
     * İmza dış katmanda doğrulanır; burada şunlar kontrol edilir:
     *  - aud bizim client ID'lerimizden biri (token BAŞKA uygulama için üretilmemiş)
     *  - iss Google
     *  - exp geçmemiş
     *  - email var ve email_verified true (hesap bağlama e-postaya güvenir)
     */
    public static function validateClaims(
        array $claims,
        array $clientIds,
        ?int $now = null,
    ): bool {
        $now ??= time();

        $aud = (string) ($claims['aud'] ?? '');
        if ($aud === '' || !in_array($aud, $clientIds, true)) {
            return false;
        }

        $iss = (string) ($claims['iss'] ?? '');
        if (!in_array($iss, self::VALID_ISSUERS, true)) {
            return false;
        }

        $exp = (int) ($claims['exp'] ?? 0);
        if ($exp <= $now) {
            return false;
        }

        $email = (string) ($claims['email'] ?? '');
        // tokeninfo bool alanları string döndürür ("true"/"false"); JWKS yolunda
        // gerçek bool gelir. İkisini de kabul et.
        $verified = ($claims['email_verified'] ?? '') === 'true'
            || ($claims['email_verified'] ?? '') === true;
        if ($email === '' || !$verified) {
            return false;
        }

        if ((string) ($claims['sub'] ?? '') === '') {
            return false;
        }

        return true;
    }

    // ── Yerel JWKS/RS256 doğrulaması ────────────────────────────────────────

    /**
     * ID token'ı Google JWKS ile yerel doğrular.
     * Dönüş: ['status' => 'ok', 'claims' => [...]] geçerli imza;
     *        ['status' => 'reject']                imza/anahtar kesin geçersiz;
     *        ['status' => 'unavailable']           yerel doğrulama yapılamadı
     *                                              (openssl yok / JWKS indirilemedi
     *                                               / beklenmeyen alg).
     */
    private static function verifyWithJwks(string $idToken): array
    {
        if (!function_exists('openssl_verify')) {
            return ['status' => 'unavailable'];
        }

        $parts = explode('.', $idToken);
        if (count($parts) !== 3) {
            return ['status' => 'reject'];
        }
        [$h64, $p64, $s64] = $parts;

        $header = json_decode(self::b64urlDecode($h64), true);
        if (!is_array($header)) {
            return ['status' => 'reject'];
        }
        // Sadece RS256 destekleniyor; farklı alg gelirse tokeninfo'ya bırak.
        if (($header['alg'] ?? '') !== 'RS256') {
            return ['status' => 'unavailable'];
        }
        $kid = (string) ($header['kid'] ?? '');
        if ($kid === '') {
            return ['status' => 'reject'];
        }

        $jwk = self::findJwk($kid);
        if ($jwk === null) {
            // Anahtar cache'te yoksa dönmüş olabilir → bir kez zorla yenile.
            $jwk = self::findJwk($kid, true);
        }
        if ($jwk === null) {
            // JWKS hiç indirilemediyse fallback'e izin ver; indirilip de kid
            // yoksa bu gerçekten geçersiz bir token demektir.
            return self::$jwksFetchFailed ? ['status' => 'unavailable'] : ['status' => 'reject'];
        }
        if (($jwk['kty'] ?? '') !== 'RSA' || !isset($jwk['n'], $jwk['e'])) {
            return ['status' => 'reject'];
        }

        $pem = self::jwkToPem((string) $jwk['n'], (string) $jwk['e']);
        if ($pem === null) {
            return ['status' => 'unavailable'];
        }

        $signature = self::b64urlDecode($s64);
        $ok = openssl_verify("$h64.$p64", $signature, $pem, OPENSSL_ALGO_SHA256);
        if ($ok !== 1) {
            return ['status' => 'reject'];
        }

        $claims = json_decode(self::b64urlDecode($p64), true);
        if (!is_array($claims)) {
            return ['status' => 'reject'];
        }
        return ['status' => 'ok', 'claims' => $claims];
    }

    /** Son JWKS indirmesinin başarısız olup olmadığı (fallback kararı için). */
    private static bool $jwksFetchFailed = false;

    /** Verilen kid için JWK'yı cache'ten/ağdan bulur; yoksa null. */
    private static function findJwk(string $kid, bool $forceRefresh = false): ?array
    {
        $keys = self::fetchJwks($forceRefresh);
        if ($keys === null) {
            return null;
        }
        foreach ($keys as $k) {
            if (is_array($k) && ($k['kid'] ?? '') === $kid) {
                return $k;
            }
        }
        return null;
    }

    /**
     * Google JWKS anahtar listesini döner (cache'li). İndirilemezse ve cache de
     * yoksa null. Ağ hatasında süresi geçmiş cache varsa yine de kullanılır
     * (anahtarlar günlerce geçerlidir).
     */
    private static function fetchJwks(bool $forceRefresh = false): ?array
    {
        self::$jwksFetchFailed = false;
        $cacheFile = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'cinema_google_jwks.json';

        $cached = null;
        if (is_readable($cacheFile)) {
            $decoded = json_decode((string) file_get_contents($cacheFile), true);
            if (is_array($decoded) && isset($decoded['keys']) && is_array($decoded['keys'])) {
                $cached = $decoded;
                $fresh = ((int) ($decoded['fetched_at'] ?? 0)) + self::JWKS_CACHE_TTL > time();
                if (!$forceRefresh && $fresh) {
                    return $decoded['keys'];
                }
            }
        }

        $ch = curl_init(self::JWKS_URL);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 8,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
        ]);
        $body = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($body === false || $status !== 200) {
            // Ağ hatası: elde varsa süresi geçmiş cache'i kullan, yoksa işaretle.
            if ($cached !== null) {
                return $cached['keys'];
            }
            self::$jwksFetchFailed = true;
            return null;
        }

        $data = json_decode((string) $body, true);
        if (!is_array($data) || !isset($data['keys']) || !is_array($data['keys'])) {
            if ($cached !== null) {
                return $cached['keys'];
            }
            self::$jwksFetchFailed = true;
            return null;
        }

        @file_put_contents(
            $cacheFile,
            json_encode(['fetched_at' => time(), 'keys' => $data['keys']]),
            LOCK_EX,
        );
        return $data['keys'];
    }

    /**
     * JWK (RSA modulus n + exponent e, base64url) → PEM public key.
     * ASN.1/DER SubjectPublicKeyInfo elle kodlanır; harici kütüphane gerekmez.
     * Hata durumunda null.
     */
    private static function jwkToPem(string $nB64, string $eB64): ?string
    {
        $modulus = self::b64urlDecode($nB64);
        $exponent = self::b64urlDecode($eB64);
        if ($modulus === '' || $exponent === '') {
            return null;
        }

        // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        $rsaPublicKey = self::derSequence(
            self::derInteger($modulus) . self::derInteger($exponent),
        );

        // AlgorithmIdentifier: rsaEncryption (1.2.840.113549.1.1.1) + NULL
        $algId = "\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00";

        // subjectPublicKey BIT STRING (0 kullanılmayan bit) içinde RSAPublicKey.
        $bitString = "\x03" . self::derLength(strlen($rsaPublicKey) + 1) . "\x00" . $rsaPublicKey;

        $spki = self::derSequence($algId . $bitString);

        $pem = "-----BEGIN PUBLIC KEY-----\n"
            . chunk_split(base64_encode($spki), 64, "\n")
            . "-----END PUBLIC KEY-----\n";

        return $pem;
    }

    private static function derSequence(string $contents): string
    {
        return "\x30" . self::derLength(strlen($contents)) . $contents;
    }

    private static function derInteger(string $bytes): string
    {
        // Baştaki gereksiz sıfırları at, tamamen boşsa tek sıfır bırak.
        $bytes = ltrim($bytes, "\x00");
        if ($bytes === '') {
            $bytes = "\x00";
        }
        // En anlamlı bit set ise pozitif olduğunu belirtmek için 0x00 ekle.
        if ((ord($bytes[0]) & 0x80) !== 0) {
            $bytes = "\x00" . $bytes;
        }
        return "\x02" . self::derLength(strlen($bytes)) . $bytes;
    }

    private static function derLength(int $len): string
    {
        if ($len < 0x80) {
            return chr($len);
        }
        $out = '';
        while ($len > 0) {
            $out = chr($len & 0xff) . $out;
            $len >>= 8;
        }
        return chr(0x80 | strlen($out)) . $out;
    }

    private static function b64urlDecode(string $d): string
    {
        return (string) base64_decode(strtr($d, '-_', '+/'), true);
    }

    /** tokeninfo çağrısı (fallback); ağ/HTTP hatasında veya 200 dışında null. */
    private static function fetchTokenInfo(string $idToken): ?array
    {
        $ch = curl_init(self::TOKENINFO_URL . urlencode($idToken));
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 8,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_HTTPHEADER     => ['Accept: application/json'],
        ]);
        $body = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($body === false || $status !== 200) {
            return null;
        }
        $data = json_decode((string) $body, true);
        return is_array($data) ? $data : null;
    }
}
