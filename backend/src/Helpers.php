<?php
declare(strict_types=1);
// Ortak yardımcılar: JSON yanıt, gövde okuma, basit rate-limit.

function now_ms(): int { return (int) round(microtime(true) * 1000); }

function json_out(int $status, array $body): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(int $status, string $msg): void
{
    json_out($status, ['error' => $msg]);
}

/** İstek gövdesini JSON olarak okur. */
function read_json(): array
{
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

/** Authorization: Bearer <token> başlığından token'ı çeker. */
function bearer_token(): ?string
{
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($hdr === '' && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $hdr = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    if (preg_match('/Bearer\s+(.+)/i', $hdr, $m)) return trim($m[1]);
    return null;
}

/**
 * Dosya tabanlı, IP başına dakikalık basit rate-limit.
 * Paylaşımlı hosting için yeterli; ölçeklenince Redis/DB'ye taşı.
 */
function rate_limit(string $bucket, int $perMin): void
{
    $ip  = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $key = preg_replace('/[^a-z0-9_]/i', '_', "$bucket-$ip");
    $file = sys_get_temp_dir() . "/rl_$key";
    $win  = (int) floor(time() / 60);
    $cur  = @json_decode((string) @file_get_contents($file), true);
    if (!is_array($cur) || ($cur['win'] ?? -1) !== $win) {
        $cur = ['win' => $win, 'n' => 0];
    }
    $cur['n']++;
    @file_put_contents($file, json_encode($cur), LOCK_EX);
    if ($cur['n'] > $perMin) {
        fail(429, 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.');
    }
}
