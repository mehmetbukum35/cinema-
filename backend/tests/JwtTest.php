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
}
