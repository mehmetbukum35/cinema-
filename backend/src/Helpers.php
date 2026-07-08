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

/** İstek gövdesini JSON olarak okur. Aşırı büyük gövdeler 413 ile reddedilir. */
function read_json(int $maxBytes = 4 * 1024 * 1024): array
{
    $raw = file_get_contents('php://input') ?: '';
    if (strlen($raw) > $maxBytes) {
        fail(413, 'İstek gövdesi çok büyük.');
    }
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
 * Veritabanı tabanlı, IP/Kullanıcı başına dakikalık basit rate-limit.
 * DB hatasında failClosed=true ise 503 fırlatır, yoksa loglayıp geçişe izin verir (fail-open).
 */
function rate_limit(string $bucket, int $perMin, bool $failClosed = false): void
{
    $ip  = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $key = preg_replace('/[^a-z0-9_]/i', '_', "$bucket-$ip");
    $win  = (int) floor(time() / 60);

    try {
        $db = Db::conn();
        
        // Temizlik: 5 dakika öncesine ait pencereleri periyodik olarak temizleyelim (sorgu yükü olmaması için)
        // Her 20 istekten birinde temizlik yapsın (random temizlik)
        if (mt_rand(1, 20) === 1) {
            $stmtClean = $db->prepare("DELETE FROM rate_limits WHERE window_time < ?");
            $stmtClean->execute([$win - 5]);
        }

        $driver = $db->getAttribute(PDO::ATTR_DRIVER_NAME);
        if ($driver === 'sqlite') {
            // SQLite için ON CONFLICT DO UPDATE
            $stmt = $db->prepare("
                INSERT INTO rate_limits (ip_bucket, window_time, request_count)
                VALUES (?, ?, 1)
                ON CONFLICT(ip_bucket, window_time) DO UPDATE SET request_count = request_count + 1
            ");
        } else {
            // MySQL/MariaDB için ON DUPLICATE KEY UPDATE
            $stmt = $db->prepare("
                INSERT INTO rate_limits (ip_bucket, window_time, request_count)
                VALUES (?, ?, 1)
                ON DUPLICATE KEY UPDATE request_count = request_count + 1
            ");
        }
        $stmt->execute([$key, $win]);

        // Mevcut sayıyı oku
        $stmtGet = $db->prepare("SELECT request_count FROM rate_limits WHERE ip_bucket = ? AND window_time = ?");
        $stmtGet->execute([$key, $win]);
        $row = $stmtGet->fetch();
        
        $count = $row ? (int) $row['request_count'] : 1;
        if ($count > $perMin) {
            fail(429, 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.');
        }
    } catch (Throwable $e) {
        // Testlerde fail() çağrısının fırlattığı istisna yakalanmamalı (yoksa 429 testi geçemez).
        if (get_class($e) === 'TestExitException') {
            throw $e;
        }
        cinema_error("Rate limit DB error: " . $e->getMessage());
        if ($failClosed) {
            fail(503, 'Geçici hizmet kısıtı.');
        }
    }
}

/**
 * cinema+ merkezi hata loglama yardımcı fonksiyonu.
 * Bağlamsal verileri (IP, Rota, Kullanıcı ID) otomatik ekler.
 */
function cinema_error(string $message, ?int $uid = null, ?string $route = null): void
{
    $uidStr = $uid !== null ? " [UID: $uid]" : "";
    $routeStr = $route !== null ? " [Route: $route]" : "";
    if ($route === null) {
        $routeStr = isset($_SERVER['REQUEST_URI']) ? " [Route: " . $_SERVER['REQUEST_URI'] . "]" : "";
    }
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    error_log("cinema+ ERROR$uidStr$routeStr [IP: $ip]: $message");
}
