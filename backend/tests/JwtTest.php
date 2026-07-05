<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/Jwt.php';

/**
 * Jwt sinifi icin birim testler.
 * Dis bagimlilik yok - Jwt tamamen statik ve izole.
 */
class JwtTest extends TestCase
{
    private const SECRET = 'test-super-secret-key-for-unit-tests';

    // --- encode + decode basari yolu ----------------------------------------

    public function testEncodeAndDecodeRoundTrip(): void
    {
        $payload = ['sub' => 42, 'typ' => 'access', 'exp' => time() + 3600];

        $token = Jwt::encode($payload, self::SECRET);

        $this->assertIsString($token);
        // JWT uclu yapi: header.payload.signature
        $this->assertSame(3, substr_count($token, '.') + 1);

        $decoded = Jwt::decode($token, self::SECRET);
        $this->assertIsArray($decoded);
        $this->assertSame(42,       $decoded['sub']);
        $this->assertSame('access', $decoded['typ']);
    }

    // --- Yanlish gizli anahtar imzayi gecersiz kilar -------------------------

    public function testDecodeReturnsFalseOnWrongSecret(): void
    {
        $token = Jwt::encode(['sub' => 1, 'exp' => time() + 3600], self::SECRET);
        $result = Jwt::decode($token, 'wrong-secret');
        $this->assertNull($result, 'Yanlish secret ile decode null donmeli.');
    }

    // --- Suresi dolmus token reddedilir (exp = gecmis zaman) -----------------

    public function testDecodeRejectsExpiredToken(): void
    {
        $payload = ['sub' => 7, 'typ' => 'access', 'exp' => time() - 1];
        $token = Jwt::decode(Jwt::encode($payload, self::SECRET), self::SECRET);
        $this->assertNull($token, 'Suresi dolmus token null donmeli.');
    }

    // --- exp alani yoksa token suresiz kabul edilir --------------------------

    public function testDecodeAcceptsTokenWithoutExp(): void
    {
        $payload = ['sub' => 99, 'role' => 'admin'];
        $token = Jwt::encode($payload, self::SECRET);
        $decoded = Jwt::decode($token, self::SECRET);
        $this->assertIsArray($decoded);
        $this->assertSame(99, $decoded['sub']);
    }

    // --- Bozuk token formati: uc kisim degil ---------------------------------

    public function testDecodeRejectsMalformedToken(): void
    {
        $this->assertNull(Jwt::decode('not.a.valid.jwt', self::SECRET));
        $this->assertNull(Jwt::decode('onlytwoparts.here', self::SECRET));
        $this->assertNull(Jwt::decode('', self::SECRET));
    }

    // --- Imza kismi kurcalanmis --------------------------------------------

    public function testDecodeRejectsTamperedSignature(): void
    {
        $token = Jwt::encode(['sub' => 5, 'exp' => time() + 3600], self::SECRET);
        $parts = explode('.', $token);
        // Son karakteri degistir
        $parts[2] = substr($parts[2], 0, -1) . ($parts[2][-1] === 'A' ? 'B' : 'A');
        $tampered = implode('.', $parts);
        $this->assertNull(Jwt::decode($tampered, self::SECRET), 'Kurcalanmis token null donmeli.');
    }

    // --- Payload kismi kurcalanmis ------------------------------------------

    public function testDecodeRejectsTamperedPayload(): void
    {
        $token = Jwt::encode(['sub' => 1, 'exp' => time() + 3600], self::SECRET);
        $parts = explode('.', $token);
        // Payload'i degistir: sub=1 -> sub=999
        $fakePayload = base64_encode(json_encode(['sub' => 999, 'exp' => time() + 3600]));
        $parts[1] = rtrim(strtr($fakePayload, '+/', '-_'), '=');
        $tampered  = implode('.', $parts);
        $this->assertNull(Jwt::decode($tampered, self::SECRET), 'Kurcalanmis payload null donmeli.');
    }

    // --- Refresh token turu access token ile ayirt edilebilir ---------------

    public function testTokenTypeDistinction(): void
    {
        $access  = Jwt::encode(['sub' => 1, 'typ' => 'access',  'exp' => time() + 900],  self::SECRET);
        $refresh = Jwt::encode(['sub' => 1, 'typ' => 'refresh', 'exp' => time() + 86400], self::SECRET);

        $decodedAccess  = Jwt::decode($access,  self::SECRET);
        $decodedRefresh = Jwt::decode($refresh, self::SECRET);

        $this->assertSame('access',  $decodedAccess['typ']);
        $this->assertSame('refresh', $decodedRefresh['typ']);
        $this->assertNotEquals($access, $refresh);
    }

    // --- Key Rotation ve kid desteği testleri ---------------------------------

    public function testEncodeAndDecodeWithSecretArrayKeyRotation(): void
    {
        $secrets = [
            'v1' => 'old-secret-key-12345',
            'v2' => 'new-secret-key-67890', // active
        ];

        $payload = ['sub' => 101, 'exp' => time() + 3600];

        // active key (v2) ile encode edilmeli
        $token = Jwt::encode($payload, $secrets);

        // header'da kid = v2 olmalı
        $parts = explode('.', $token);
        $header = json_decode(base64_decode(strtr($parts[0], '-_', '+/')), true);
        $this->assertSame('v2', $header['kid']);

        // decode edebilmeli
        $decoded = Jwt::decode($token, $secrets);
        $this->assertIsArray($decoded);
        $this->assertSame(101, $decoded['sub']);
    }

    public function testDecodeAcceptsTokenSignedWithOlderConfiguredSecret(): void
    {
        $secrets = [
            'v1' => 'old-secret-key-12345',
            'v2' => 'new-secret-key-67890', // active
        ];

        $payload = ['sub' => 102, 'exp' => time() + 3600];

        // Eski anahtarla (v1) token imzalıyoruz
        $token = Jwt::encode($payload, $secrets, 'v1');

        $parts = explode('.', $token);
        $header = json_decode(base64_decode(strtr($parts[0], '-_', '+/')), true);
        $this->assertSame('v1', $header['kid']);

        // decode işlemi hem v1 hem de v2'yi bildiği için başarılı olmalı
        $decoded = Jwt::decode($token, $secrets);
        $this->assertIsArray($decoded);
        $this->assertSame(102, $decoded['sub']);
    }

    public function testDecodeRejectsTokenWithNoneAlgorithm(): void
    {
        $payload = ['sub' => 103, 'exp' => time() + 3600];

        // "alg": "none" saldırısı için sahte bir token üretiyoruz
        $header = ['alg' => 'none', 'typ' => 'JWT'];
        $h = rtrim(strtr(base64_encode(json_encode($header)), '+/', '-_'), '=');
        $p = rtrim(strtr(base64_encode(json_encode($payload)), '+/', '-_'), '=');
        $tamperedToken = "$h.$p.";

        $decoded = Jwt::decode($tamperedToken, self::SECRET);
        $this->assertNull($decoded, 'alg: none olan token decode edilmemeli, null dönmeli.');
    }

    public function testDecodeRejectsTokenWithMissingOrUnknownKidInSecretArray(): void
    {
        $secrets = [
            'v2' => 'new-secret-key-67890',
        ];

        // 'v1' kid'ine sahip token üretiyoruz
        $token = Jwt::encode(['sub' => 104], ['v1' => 'old-secret-key-12345'], 'v1');

        // Config'de 'v1' olmadığı için decode edilmemeli
        $decoded = Jwt::decode($token, $secrets);
        $this->assertNull($decoded, 'Unknown kid olan token null dönmeli.');
    }
}
