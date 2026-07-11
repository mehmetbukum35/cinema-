<?php
declare(strict_types=1);

// Sign in with Apple identity token doğrulaması.
//
// GoogleAuth ile aynı strateji: Apple'ın JWKS ucu (https://appleid.apple.com/auth/keys)
// indirilip cache'lenir; identity token'ın RS256 imzası openssl ile YEREL doğrulanır.
// Apple'da tokeninfo benzeri bir fallback ucu YOKTUR — JWKS indirilemezse giriş
// reddedilir (güvenlikten ödün verilmez). Composer/kütüphane gerekmez.
//
// Google'dan farklar:
//  - aud, OAuth client ID değil UYGULAMANIN BUNDLE ID'sidir (com.mehmet.neizlesem).
//  - Kullanıcı adı token'da YOKTUR; istemci ilk yetkilendirmede ayrıca gönderir.
//  - email_verified bool ya da "true"/"false" string gelebilir.
//  - Kullanıcı "e-postamı gizle" seçtiyse email @privaterelay.appleid.com olur;
//    normal e-posta gibi işlenir (Apple bu adrese iletim yapar).
class AppleAuth
{
    private const JWKS_URL = 'https://appleid.apple.com/auth/keys';
    private const VALID_ISSUER = 'https://appleid.apple.com';
    // Apple anahtarları uzun ömürlü; 6 saatlik cache güvenli ve azdır.
    private const JWKS_CACHE_TTL = 21600;

    /**
     * Identity token'ı doğrulayıp claim'leri döner; geçersizse null.
     * $bundleIds: kabul edilen uygulama bundle ID'leri (aud bunlardan biri olmalı).
     */
    public static function verifyIdentityToken(string $idToken, array $bundleIds): ?array
    {
        $result = self::verifyWithJwks($idToken);
        if ($result['status'] !== 'ok') {
            return null;
        }
        return self::validateClaims($result['claims'], $bundleIds) ? $result['claims'] : null;
    }

    /**
     * Saf claim doğrulaması (ağ yok) — birim testlerin hedefi.
     * İmza dış katmanda doğrulanır; burada şunlar kontrol edilir:
     *  - aud bizim bundle ID'lerimizden biri (token BAŞKA uygulama için üretilmemiş)
     *  - iss Apple
     *  - exp geçmemiş
     *  - sub var (Apple'ın değişmez kullanıcı kimliği)
     *  - email varsa email_verified true olmalı (hesap bağlama e-postaya güvenir)
     */
    public static function validateClaims(
        array $claims,
        array $bundleIds,
        ?int $now = null,
    ): bool {
        $now ??= time();

        $aud = (string) ($claims['aud'] ?? '');
        if ($aud === '' || !in_array($aud, $bundleIds, true)) {
            return false;
        }

        if ((string) ($claims['iss'] ?? '') !== self::VALID_ISSUER) {
            return false;
        }

        $exp = (int) ($claims['exp'] ?? 0);
        if ($exp <= $now) {
            return false;
        }

        if ((string) ($claims['sub'] ?? '') === '') {
            return false;
        }

        // Apple email_verified'ı bool ya da string gönderebilir.
        $email = (string) ($claims['email'] ?? '');
        if ($email !== '') {
            $verified = ($claims['email_verified'] ?? '') === 'true'
                || ($claims['email_verified'] ?? '') === true;
            if (!$verified) {
                return false;
            }
        }

        return true;
    }

    // ── Yerel JWKS/RS256 doğrulaması (GoogleAuth ile aynı teknik) ───────────

    /** @return array{status:string, claims?:array} */
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
        if (!is_array($header) || ($header['alg'] ?? '') !== 'RS256') {
            return ['status' => 'reject'];
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
        if ($jwk === null || ($jwk['kty'] ?? '') !== 'RSA' || !isset($jwk['n'], $jwk['e'])) {
            return ['status' => 'reject'];
        }

        $pem = self::jwkToPem((string) $jwk['n'], (string) $jwk['e']);
        if ($pem === null) {
            return ['status' => 'reject'];
        }

        $signature = self::b64urlDecode($s64);
        if (openssl_verify("$h64.$p64", $signature, $pem, OPENSSL_ALGO_SHA256) !== 1) {
            return ['status' => 'reject'];
        }

        $claims = json_decode(self::b64urlDecode($p64), true);
        if (!is_array($claims)) {
            return ['status' => 'reject'];
        }
        return ['status' => 'ok', 'claims' => $claims];
    }

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
     * Apple JWKS anahtar listesini döner (cache'li). Ağ hatasında süresi geçmiş
     * cache varsa yine de kullanılır (anahtarlar uzun ömürlüdür).
     */
    private static function fetchJwks(bool $forceRefresh = false): ?array
    {
        $cacheFile = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'cinema_apple_jwks.json';

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
            // Hosting'de IPv6 çıkışı bozuk: Apple'a IPv4 ile bağlan.
            CURLOPT_IPRESOLVE      => CURL_IPRESOLVE_V4,
        ]);
        $body = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($body === false || $status !== 200) {
            return $cached !== null ? $cached['keys'] : null;
        }

        $data = json_decode((string) $body, true);
        if (!is_array($data) || !isset($data['keys']) || !is_array($data['keys'])) {
            return $cached !== null ? $cached['keys'] : null;
        }

        @file_put_contents(
            $cacheFile,
            json_encode(['fetched_at' => time(), 'keys' => $data['keys']]),
            LOCK_EX,
        );
        return $data['keys'];
    }

    /** JWK (RSA n+e, base64url) → PEM public key. GoogleAuth::jwkToPem ile aynı. */
    private static function jwkToPem(string $nB64, string $eB64): ?string
    {
        $modulus = self::b64urlDecode($nB64);
        $exponent = self::b64urlDecode($eB64);
        if ($modulus === '' || $exponent === '') {
            return null;
        }

        $rsaPublicKey = self::derSequence(
            self::derInteger($modulus) . self::derInteger($exponent),
        );
        $algId = "\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00";
        $bitString = "\x03" . self::derLength(strlen($rsaPublicKey) + 1) . "\x00" . $rsaPublicKey;
        $spki = self::derSequence($algId . $bitString);

        return "-----BEGIN PUBLIC KEY-----\n"
            . chunk_split(base64_encode($spki), 64, "\n")
            . "-----END PUBLIC KEY-----\n";
    }

    private static function derSequence(string $contents): string
    {
        return "\x30" . self::derLength(strlen($contents)) . $contents;
    }

    private static function derInteger(string $bytes): string
    {
        $bytes = ltrim($bytes, "\x00");
        if ($bytes === '') {
            $bytes = "\x00";
        }
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
}
