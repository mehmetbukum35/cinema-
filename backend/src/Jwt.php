<?php
declare(strict_types=1);
// Bağımlılıksız JWT (HS256). Paylaşımlı hosting'de composer gerekmez.
class Jwt
{
    public static function encode(array $payload, string|array $secret, ?string $kid = null): string
    {
        $header = ['alg' => 'HS256', 'typ' => 'JWT'];
        $verificationSecret = $secret;
        if (is_array($secret)) {
            $activeKid = $kid ?? (string)array_key_last($secret);
            $header['kid'] = $activeKid;
            $verificationSecret = $secret[$activeKid];
        }
        $h = self::b64(json_encode($header));
        $p = self::b64(json_encode($payload));
        $sig = self::b64(hash_hmac('sha256', "$h.$p", $verificationSecret, true));
        return "$h.$p.$sig";
    }

    /** Geçerliyse payload dizisini, değilse null döner (imza + exp kontrolü). */
    public static function decode(string $jwt, string|array $secret): ?array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) return null;
        [$h, $p, $s] = $parts;

        $header = json_decode(self::b64d($h), true);
        if (!is_array($header)) return null;

        // algorithm confusion ve "alg: none" saldırı koruması
        if (!isset($header['alg']) || $header['alg'] !== 'HS256') {
            return null;
        }

        $verificationSecret = $secret;
        if (is_array($secret)) {
            $kid = $header['kid'] ?? null;
            if ($kid === null || !isset($secret[$kid])) {
                return null; // kid header'da yok veya konfigürasyonda bulunamadı
            }
            $verificationSecret = $secret[$kid];
        }

        $expected = self::b64(hash_hmac('sha256', "$h.$p", $verificationSecret, true));
        if (!hash_equals($expected, $s)) return null;
        $payload = json_decode(self::b64d($p), true);
        if (!is_array($payload)) return null;
        if (isset($payload['exp']) && time() >= (int)$payload['exp']) return null;
        return $payload;
    }

    private static function b64(string $d): string
    {
        return rtrim(strtr(base64_encode($d), '+/', '-_'), '=');
    }

    private static function b64d(string $d): string
    {
        return base64_decode(strtr($d, '-_', '+/')) ?: '';
    }
}
