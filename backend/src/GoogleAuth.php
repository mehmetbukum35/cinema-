<?php
declare(strict_types=1);

// Google Sign-In ID token doğrulaması.
//
// Neden tokeninfo ucu: paylaşımlı hosting'de RS256/JWKS kripto bağımlılığı
// eklememek için Google'ın resmî düşük-hacim doğrulama ucu kullanılır
// (https://oauth2.googleapis.com/tokeninfo). Google imzayı orada doğrular;
// biz yalnızca claim'leri (aud/iss/exp/email_verified) kontrol ederiz.
// Karar mantığı [validateClaims] içinde saf ve test edilebilirdir.
class GoogleAuth
{
    private const TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo?id_token=';
    private const VALID_ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];

    /**
     * ID token'ı Google'a doğrulatıp claim'leri döner; geçersizse null.
     * $clientIds: kabul edilen OAuth client ID'leri (aud bunlardan biri olmalı).
     */
    public static function verifyIdToken(string $idToken, array $clientIds): ?array
    {
        $claims = self::fetchTokenInfo($idToken);
        if ($claims === null) {
            return null;
        }
        return self::validateClaims($claims, $clientIds) ? $claims : null;
    }

    /**
     * Saf claim doğrulaması (ağ yok) — birim testlerin hedefi.
     * tokeninfo imzayı zaten doğrular; burada şunlar kontrol edilir:
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
        // tokeninfo bool alanları string döndürür ("true"/"false").
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

    /** tokeninfo çağrısı; ağ/HTTP hatasında veya 200 dışında null. */
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
