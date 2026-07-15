<?php
declare(strict_types=1);
// Ortak yardımcılar: JSON yanıt, gövde okuma, basit rate-limit.

if (!function_exists('now_ms')) {
    function now_ms(): int { return (int) round(microtime(true) * 1000); }
}

if (!function_exists('json_out')) {
    function json_out(int $status, array $body): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        cinema_send_request_id_header();
        echo json_encode($body, JSON_UNESCAPED_UNICODE);
        exit;
    }
}

if (!function_exists('fail')) {
    /**
     * Hata yanıtı. $code, istemcinin YEREL metinlere çevirmek için kullandığı
     * makine-okur anahtardır (ör. 'email_unverified'). İnsan-okur $msg
     * serbestçe düzenlenebilir; istemci davranışı yalnızca $code'a bağlıdır —
     * eskiden istemci Türkçe cümleleri birebir eşliyordu ve bir yazım
     * düzeltmesi akışları sessizce bozabiliyordu.
     */
    function fail(int $status, string $msg, ?string $code = null): void
    {
        $body = ['error' => $msg, 'request_id' => cinema_request_id()];
        if ($code !== null) {
            $body['code'] = $code;
        }
        json_out($status, $body);
    }
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
if (!function_exists('bearer_token')) {
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
            fail(429, 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.', 'rate_limited');
        }
    } catch (Throwable $e) {
        // Testlerde fail() çağrısının fırlattığı istisna yakalanmamalı (yoksa 429 testi geçemez).
        if (get_class($e) === 'TestExitException') {
            throw $e;
        }
        cinema_error("Rate limit DB error: " . $e->getMessage());
        if ($failClosed) {
            fail(503, 'Geçici hizmet kısıtı.', 'rate_limited');
        }
    }
}

/**
 * Kullanıcı yorumunu sunucu tarafında normalize eder. İstemci 280 karakterle
 * sınırlar ama API'ye güvenilmez: kontrol karakterleri temizlenir, URL'ler
 * sökülür (reklam/spam vektörü), 280 karaktere kırpılır. Boş kalan yorum NULL
 * olur ki sorgulardaki `comment IS NOT NULL AND comment <> ''` filtresi işlesin.
 */
function sanitize_comment(?string $c): ?string
{
    if ($c === null) return null;
    $c = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/u', '', $c) ?? '';
    $c = preg_replace('~(?:https?://|www\.)[^\s]+~iu', '', $c) ?? '';
    $c = preg_replace('/[ \t]{2,}/u', ' ', $c) ?? '';
    $c = trim($c);
    if ($c === '') return null;
    return function_exists('mb_substr') ? mb_substr($c, 0, 280, 'UTF-8') : substr($c, 0, 280);
}

/** Leetspeak / rakam taklidi → harf (küfür normalizasyonu). */
function profanity_decode_leet(string $s): string
{
    static $map = [
        '@' => 'a', '4' => 'a', '8' => 'b', '3' => 'e', '6' => 'g',
        '1' => 'i', '!' => 'i', '|' => 'i', '0' => 'o', '5' => 's',
        '$' => 's', '7' => 't', '2' => 'z',
    ];
    return strtr($s, $map);
}

/** Tekrarlı karakterleri söker: amkkk → amk. */
function profanity_collapse_repeats(string $s): string
{
    return preg_replace('/(.)\1{2,}/u', '$1', $s) ?? $s;
}

/** Türkçe aksanları ASCII'ye indirger (kasıtlı yazım hataları için). */
function profanity_fold_tr(string $s): string
{
    static $map = [
        'ş' => 's', 'ç' => 'c', 'ğ' => 'g', 'ı' => 'i', 'ö' => 'o', 'ü' => 'u',
        'â' => 'a', 'î' => 'i', 'û' => 'u',
    ];
    return strtr($s, $map);
}

/** Ayraç/boşluk temizlenmiş kompakt akış (a.m.k → amk). */
function profanity_compact(string $s): string
{
    $s = preg_replace('/[\s\.\-_\*\+,;:!?#@\/\\\|~`\'"(){}\[\]<>]+/u', '', $s) ?? $s;
    return preg_replace('/[^\p{L}\p{N}]/u', '', $s) ?? $s;
}

/**
 * Küfür kontrolü için metin varyantları: küçük harf, leet, tekrar sökme,
 * aksan indirgeme ve ayraçsız kompakt form.
 *
 * @return list<string>
 */
function profanity_variants(string $text): array
{
    $base = function_exists('mb_strtolower') ? mb_strtolower($text, 'UTF-8') : strtolower($text);
    $seen = [];
    $out  = [];

    $add = static function (string $v) use (&$seen, &$out): void {
        if ($v !== '' && !isset($seen[$v])) {
            $seen[$v] = true;
            $out[]    = $v;
        }
    };

    $leet     = profanity_decode_leet($base);
    $folded   = profanity_fold_tr($base);
    $leetFold = profanity_fold_tr($leet);

    foreach ([$base, $leet, $folded, $leetFold] as $v) {
        $add($v);
        $add(profanity_collapse_repeats($v));
    }

    foreach ($out as $v) {
        $add(profanity_compact($v));
    }

    return $out;
}

/** Kelime sınırı ile tam eşleşme (tamam içindeki am gibi yanlış pozitifleri önler). */
function profanity_has_word(string $haystack, string $word): bool
{
    return (bool) preg_match(
        '/(?<![\p{L}\p{N}])' . preg_quote($word, '/') . '(?![\p{L}\p{N}])/u',
        $haystack
    );
}

/**
 * TR+EN küfür/spam tespiti: genişletilmiş kelime listesi, leetspeak, boşluk/ayraç
 * ve tekrarlı karakter obfuscation'ına karşı normalizasyon. Kusursuz değildir —
 * amaç bariz vakaları otomatik gizleyip (is_hidden=1) gerisini şikayet mekanizmasına
 * bırakmaktır. Yorum kullanıcının kendi cihazında görünmeye devam eder.
 */
function comment_flagged(string $c): bool
{
    static $boundaryWords = null;
    static $compactWords = null;
    static $patterns = null;

    if ($boundaryWords === null) {
        $boundaryWords = [
            // TR — bariz küfür
            'amk', 'amq', 'amına', 'amcik', 'amcık', 'amini', 'aminakoyim', 'aminakoyayim',
            'aq', 'orospu', 'orosbu', 'orospucocugu', 'orospucocuğu', 'oç', 'oc',
            'piç', 'pic', 'pıç', 'sik', 'sikerim', 'sikeyim', 'sikiyim', 'siktim',
            'sikik', 'siktiğim', 'siktigim', 'sikmiş', 'sikmis', 'sokayım', 'sokayim',
            'yarrak', 'yarak', 'göt', 'gotun', 'götün', 'gotune', 'götüne', 'götveren',
            'ibne', 'ibine', 'pezevenk', 'kahpe', 'gavat', 'yavşak', 'yavsak',
            'şerefsiz', 'serefsiz', 'puşt', 'pust', 'dingil', 'dalyarak', 'malafat',
            'ananı', 'anani', 'anasını', 'anasini', 'sürtük', 'surtuk', 'kerhane',
            'bok', 'boktan', 'sikimsonik', 'godoş', 'godos',
            // EN
            'fuck', 'fucking', 'fucker', 'fucked', 'fuk', 'fck', 'shit', 'sh1t',
            'bitch', 'b1tch', 'asshole', 'cunt', 'faggot', 'fag', 'nigger', 'nigga',
            'dick', 'd1ck', 'pussy', 'whore', 'bastard', 'motherfucker', 'wtf',
            // spam/reklam
            'bahis', 'casino', 'bet365', 'kumarhane', 'porno', 'escort', 'viagra',
        ];

        // Kompakt akışta yalnızca ayırt edici uzun formlar (topic→pic, boks→bok yanlış pozitifi yok).
        $compactWords = [
            'amk', 'amq', 'orospu', 'orosbu', 'yarrak', 'pezevenk', 'kahpe', 'gavat',
            'dalyarak', 'malafat', 'sikimsonik', 'godos', 'aminakoyim', 'aminakoyayim',
            'orospucocugu', 'motherfucker', 'asshole', 'kumarhane', 'bet365', 'viagra',
        ];

        $patterns = [
            // TR — ayraç/boşluk obfuscation
            '/(?<![\p{L}\p{N}])a[\W_]*m[\W_]*k(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])a[\W_]*q(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])o[\W_]*[çc](?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])p[\W_]*[iı][\W_]*[çc](?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])s[\W_]*i[\W_]*k(?:erim|iyim|tim|tir|ik|mis|miş|iyor)?(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])y[\W_]*a[\W_]*r[\W_]*a[\W_]*k(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])g[oö0][\W_]*t(?:[uü]n|[uü]ne|veren)(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])or[\W_]*o[\W_]*s[\W_]*p[\W_]*u(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])a[\W_]*m[\W_]*[cç][\W_]*[iı][\W_]*k(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])a[\W_]*m[\W_]*[iı][\W_]*n[\W_]*a(?![\p{L}\p{N}])/iu',
            // EN — ayraç obfuscation
            '/(?<![\p{L}\p{N}])f[\W_]*u[\W_]*c[\W_]*k(?:ing|er|ed)?(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])s[\W_]*h[\W_]*i[\W_]*t(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])b[\W_]*i[\W_]*t[\W_]*c[\W_]*h(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])a[\W_]*s[\W_]*s[\W_]*h[\W_]*o[\W_]*l[\W_]*e(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])c[\W_]*u[\W_]*n[\W_]*t(?![\p{L}\p{N}])/iu',
            '/(?<![\p{L}\p{N}])n[\W_]*i[\W_]*g[\W_]*g[\W_]*[ae]r?(?![\p{L}\p{N}])/iu',
        ];
    }

    $variants = profanity_variants($c);

    foreach ($variants as $text) {
        foreach ($boundaryWords as $w) {
            if (profanity_has_word($text, $w)) {
                return true;
            }
        }
        foreach ($patterns as $p) {
            if (preg_match($p, $text)) {
                return true;
            }
        }
    }

    // Kompakt varyantlarda yalnızca ayırt edici uzun/kök kelimeler.
    foreach ($variants as $text) {
        $compact = profanity_compact($text);
        if ($compact === '') {
            continue;
        }
        foreach ($compactWords as $w) {
            if (str_contains($compact, $w)) {
                return true;
            }
        }
    }

    return false;
}

/**
 * cinema+ merkezi hata loglama yardımcı fonksiyonu.
 * Bağlamsal verileri (IP, Rota, Kullanıcı ID) otomatik ekler.
 */
function cinema_request_id(): string
{
    static $requestId = null;
    if ($requestId !== null) {
        return $requestId;
    }

    $incoming = trim((string) ($_SERVER['HTTP_X_REQUEST_ID'] ?? ''));
    if ($incoming !== '' && preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/', $incoming)) {
        return $requestId = $incoming;
    }

    try {
        return $requestId = bin2hex(random_bytes(16));
    } catch (Throwable) {
        return $requestId = str_replace('.', '', uniqid('', true));
    }
}

function cinema_send_request_id_header(): void
{
    if (!headers_sent()) {
        header('X-Request-ID: ' . cinema_request_id());
    }
}

/** Remove credentials and personal secrets before context reaches a log sink. */
function cinema_redact(mixed $value, ?string $key = null): mixed
{
    if ($key !== null && preg_match(
        '/password|passwd|authorization|cookie|token|secret|api[_-]?key|verification[_-]?code|reset[_-]?code/i',
        $key
    )) {
        return '[REDACTED]';
    }
    if (is_array($value)) {
        $clean = [];
        foreach ($value as $childKey => $childValue) {
            $clean[$childKey] = cinema_redact($childValue, (string) $childKey);
        }
        return $clean;
    }
    if (is_string($value)) {
        $value = preg_replace('/Bearer\s+[A-Za-z0-9._~+\/-]+=*/i', 'Bearer [REDACTED]', $value) ?? $value;
        $value = preg_replace('/([?&](?:token|key|code|secret|password)=)[^&\s]+/i', '$1[REDACTED]', $value) ?? $value;
    }
    return $value;
}

function cinema_log(string $level, string $message, array $context = []): void
{
    $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
    $route = (string) (parse_url($uri, PHP_URL_PATH) ?: '/');
    $entry = [
        'timestamp' => gmdate('c'),
        'service' => 'cinema-plus-api',
        'level' => strtoupper($level),
        'message' => cinema_redact($message),
        'request_id' => cinema_request_id(),
        'method' => $_SERVER['REQUEST_METHOD'] ?? 'CLI',
        'route' => $route,
        'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
        'context' => cinema_redact($context),
    ];
    error_log((string) json_encode($entry, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
}

/** Backwards-compatible central error logger used throughout the backend. */
function cinema_error(string $message, ?int $uid = null, ?string $route = null): void
{
    $context = [];
    if ($uid !== null) $context['user_id'] = $uid;
    if ($route !== null) $context['route_override'] = $route;
    cinema_log('error', $message, $context);
}
