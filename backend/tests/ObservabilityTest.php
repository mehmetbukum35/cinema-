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

    public function testApiSecurityPolicyDeniesBrowserCapabilities(): void
    {
        $headers = cinema_security_headers('api', false);

        self::assertSame('nosniff', $headers['X-Content-Type-Options']);
        self::assertSame('DENY', $headers['X-Frame-Options']);
        self::assertSame('no-referrer', $headers['Referrer-Policy']);
        self::assertStringContainsString("default-src 'none'", $headers['Content-Security-Policy']);
        self::assertStringContainsString("frame-ancestors 'none'", $headers['Content-Security-Policy']);
        self::assertArrayNotHasKey('Strict-Transport-Security', $headers);
    }

    public function testWebPoliciesAllowOnlyResourcesNeededByEachSurface(): void
    {
        $profile = cinema_security_headers('profile', true);
        $download = cinema_security_headers('download', true);
        $moderation = cinema_security_headers('moderation', true);

        self::assertStringContainsString('https://image.tmdb.org', $profile['Content-Security-Policy']);
        self::assertStringNotContainsString("script-src 'unsafe-inline'", $profile['Content-Security-Policy']);
        self::assertStringContainsString("script-src 'unsafe-inline'", $download['Content-Security-Policy']);
        self::assertStringContainsString("form-action 'self'", $moderation['Content-Security-Policy']);
        self::assertSame(
            'max-age=31536000; includeSubDomains',
            $profile['Strict-Transport-Security']
        );
    }
}
