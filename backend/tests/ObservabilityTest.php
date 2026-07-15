<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/Helpers.php';

final class ObservabilityTest extends TestCase
{
    public function testRedactsNestedSecretsAndBearerTokens(): void
    {
        $clean = cinema_redact([
            'email' => 'person@example.com',
            'password' => 'secret-password',
            'nested' => ['refresh_token' => 'token-value'],
            'message' => 'Authorization: Bearer abc.def.ghi',
        ]);

        self::assertSame('person@example.com', $clean['email']);
        self::assertSame('[REDACTED]', $clean['password']);
        self::assertSame('[REDACTED]', $clean['nested']['refresh_token']);
        self::assertStringNotContainsString('abc.def.ghi', $clean['message']);
    }

    public function testRequestIdHasSafeFormat(): void
    {
        self::assertMatchesRegularExpression('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/', cinema_request_id());
        self::assertSame(cinema_request_id(), cinema_request_id());
    }
}
