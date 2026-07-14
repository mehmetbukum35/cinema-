<?php
declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../src/SocialWebRenderer.php';

class TestHelperRegistry
{
    public static int $lastStatus = 200;
    public static array $lastBody = [];
    public static ?string $mockBearerToken = null;

    public static function reset(): void
    {
        self::$lastStatus = 200;
        self::$lastBody = [];
        self::$mockBearerToken = null;
    }
}

class TestExitException extends Exception {}

// Define global helpers so they don't call exit during tests
if (!function_exists('now_ms')) {
    function now_ms(): int {
        return (int) round(microtime(true) * 1000);
    }
}

if (!function_exists('json_out')) {
    function json_out(int $status, array $body): void {
        TestHelperRegistry::$lastStatus = $status;
        TestHelperRegistry::$lastBody = $body;
        // Do not call exit; in tests!
    }
}

if (!function_exists('fail')) {
    function fail(int $status, string $msg, ?string $code = null): void {
        $body = ['error' => $msg];
        if ($code !== null) {
            $body['code'] = $code;
        }
        json_out($status, $body);
        throw new TestExitException($msg, $status);
    }
}

if (!function_exists('bearer_token')) {
    function bearer_token(): ?string {
        return TestHelperRegistry::$mockBearerToken;
    }
}

// Test-üstü tanımlar yüklendikten sonra gerçek yardımcıları getir:
// guard'lı olanlar (json_out/fail/...) atlanır, sanitize_comment gibi
// yalnızca Helpers.php'de yaşayanlar kullanılabilir olur.
require_once __DIR__ . '/../src/Helpers.php';
