<?php
declare(strict_types=1);

/**
 * Paylaşılan `titles` kataloğu: client metadata geçici (fill-empty),
 * TMDB satırları kanonik (`source=tmdb`) ve client tarafından ezilemez.
 */
final class TitleCatalog
{
    public const SOURCE_CLIENT = 'client';
    public const SOURCE_TMDB = 'tmdb';

    private const FIELDS = [
        'title', 'poster_path', 'backdrop_path', 'overview', 'vote_average',
        'release_date', 'popularity', 'genre_ids',
    ];

    private const TEXT_LIMITS = [
        'title' => 512,
        'overview' => 2000,
    ];

    private const IMAGE_PATH_FIELDS = ['poster_path', 'backdrop_path'];

    /** TMDB oy ortalaması 0-10 aralığındadır; dışı veri hatasıdır. */
    private const VOTE_AVERAGE_MAX = 10.0;

    /** Gerçek TMDB popülerliği binler mertebesinde; tavan yalnız saçma değerleri keser. */
    private const POPULARITY_MAX = 1000000.0;

    /** @var array<string, array{tmdb_id:int,is_tv:int,locale:string}> */
    private array $pendingRefresh = [];

    public function __construct(
        private PDO $db,
        private ?Tmdb $tmdb = null,
        private int $lazyRefreshMax = 5,
    ) {
        $this->lazyRefreshMax = max(0, min(20, $this->lazyRefreshMax));
    }

    /**
     * Sync push'tan gelen client metadata. `source=tmdb` satırları dokunulmaz.
     * Aksi halde fill-empty + `source=client`, ardından lazy TMDB kuyruğu.
     */
    public function ingestFromClient(array $item, string $idKey, int $updatedAt, string $locale): void
    {
        $tmdbId = (int) ($item[$idKey] ?? 0);
        if ($tmdbId <= 0) {
            return;
        }
        $isTv = !empty($item['is_tv']) ? 1 : 0;

        // Geçersiz yol, aşağıdaki "hiç metadata yok" kontrolünden önce düşmeli;
        // yoksa yalnızca bozuk poster taşıyan bir push boş satır yaratır.
        foreach (self::IMAGE_PATH_FIELDS as $pathField) {
            if (array_key_exists($pathField, $item)) {
                $item[$pathField] = self::sanitizeImagePath($item[$pathField]);
            }
        }

        $hasMetadata = false;
        foreach (self::FIELDS as $field) {
            if (array_key_exists($field, $item) && $item[$field] !== null && $item[$field] !== '') {
                $hasMetadata = true;
                break;
            }
        }
        if (!$hasMetadata) {
            return;
        }

        $select = $this->db->prepare(
            'SELECT * FROM titles WHERE tmdb_id = ? AND is_tv = ? AND locale = ?'
        );
        $select->execute([$tmdbId, $isTv, $locale]);
        $existing = $select->fetch(PDO::FETCH_ASSOC);

        if ($existing !== false && ($existing['source'] ?? self::SOURCE_CLIENT) === self::SOURCE_TMDB) {
            return;
        }

        if ($existing !== false && $updatedAt < (int) $existing['metadata_updated_at']) {
            return;
        }

        $values = [
            'tmdb_id' => $tmdbId,
            'is_tv' => $isTv,
            'locale' => $locale,
            'source' => self::SOURCE_CLIENT,
        ];

        foreach (self::FIELDS as $field) {
            $incoming = $this->normalizeField($field, $item[$field] ?? null);
            if ($existing !== false) {
                $prev = $existing[$field] ?? null;
                $prevEmpty = $prev === null || $prev === '';
                if (!$prevEmpty) {
                    $values[$field] = $prev;
                    continue;
                }
            }
            $values[$field] = ($incoming === null || $incoming === '') && $existing !== false
                ? ($existing[$field] ?? null)
                : $incoming;
        }
        $values['metadata_updated_at'] = max($updatedAt, (int) ($existing['metadata_updated_at'] ?? 0));
        $values['refreshed_at'] = (int) ($existing['refreshed_at'] ?? 0);

        if ($existing === false) {
            $columns = array_keys($values);
            $list = '`' . implode('`, `', $columns) . '`';
            $placeholders = implode(', ', array_fill(0, count($columns), '?'));
            $this->db->prepare("INSERT INTO titles ($list) VALUES ($placeholders)")
                     ->execute(array_values($values));
        } else {
            $set = implode(', ', array_map(
                fn (string $field): string => "`$field` = ?",
                self::FIELDS
            ));
            $params = array_map(fn (string $field): mixed => $values[$field], self::FIELDS);
            $params[] = $values['metadata_updated_at'];
            $params[] = self::SOURCE_CLIENT;
            $params[] = $tmdbId;
            $params[] = $isTv;
            $params[] = $locale;
            $this->db->prepare(
                "UPDATE titles SET $set, metadata_updated_at = ?, source = ?
                 WHERE tmdb_id = ? AND is_tv = ? AND locale = ?"
            )->execute($params);
        }

        $this->queueRefresh($tmdbId, $isTv, $locale);
    }

    public function queueRefresh(int $tmdbId, int $isTv, string $locale): void
    {
        if ($tmdbId <= 0) {
            return;
        }
        $key = $tmdbId . ':' . $isTv . ':' . $locale;
        $this->pendingRefresh[$key] = [
            'tmdb_id' => $tmdbId,
            'is_tv' => $isTv,
            'locale' => $locale,
        ];
    }

    /** Sync transaction commit sonrası: sınırlı sayıda TMDB refresh. */
    public function flushPending(?int $max = null): int
    {
        if ($this->tmdb === null || $this->pendingRefresh === []) {
            $this->pendingRefresh = [];
            return 0;
        }
        $max ??= $this->lazyRefreshMax;
        $max = max(0, min(20, $max));
        $count = 0;
        $remaining = [];
        foreach ($this->pendingRefresh as $key => $item) {
            if ($count >= $max) {
                $remaining[$key] = $item;
                continue;
            }
            // Başarısız deneme cron'a (source=client) kalır; aynı istekte yeniden deneme.
            if ($this->refreshOne($item['tmdb_id'], $item['is_tv'], $item['locale'])) {
                $count++;
            }
        }
        $this->pendingRefresh = $remaining;
        return $count;
    }

    /**
     * Cron: `source=client` (veya hiç yenilenmemiş) satırları TMDB ile doldur.
     *
     * @return int başarıyla tmdb'ye yükseltülen satır sayısı
     */
    public function refreshStaleBatch(int $limit = 20, ?int $nowMs = null): int
    {
        if ($this->tmdb === null) {
            return 0;
        }
        $nowMs ??= (int) round(microtime(true) * 1000);
        $limit = max(1, min(100, $limit));

        $stmt = $this->db->prepare(
            "SELECT tmdb_id, is_tv, locale FROM titles
             WHERE source = ? OR refreshed_at = 0
             ORDER BY refreshed_at ASC, metadata_updated_at DESC
             LIMIT ?"
        );
        $stmt->bindValue(1, self::SOURCE_CLIENT, PDO::PARAM_STR);
        $stmt->bindValue(2, $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $count = 0;
        foreach ($rows as $row) {
            if ($this->refreshOne((int) $row['tmdb_id'], (int) $row['is_tv'], (string) $row['locale'], $nowMs)) {
                $count++;
            }
        }
        return $count;
    }

    /**
     * TMDB alanlarını kanonik olarak yazar (`source=tmdb`).
     *
     * @param array<string, mixed> $fields
     */
    public function applyTmdb(int $tmdbId, int $isTv, string $locale, array $fields, int $nowMs): bool
    {
        if ($tmdbId <= 0) {
            return false;
        }

        $values = [
            'tmdb_id' => $tmdbId,
            'is_tv' => $isTv,
            'locale' => $locale,
            'source' => self::SOURCE_TMDB,
            'refreshed_at' => $nowMs,
            'metadata_updated_at' => $nowMs,
        ];

        foreach (self::FIELDS as $field) {
            $values[$field] = $this->normalizeField($field, $fields[$field] ?? null);
        }

        $select = $this->db->prepare(
            'SELECT tmdb_id FROM titles WHERE tmdb_id = ? AND is_tv = ? AND locale = ?'
        );
        $select->execute([$tmdbId, $isTv, $locale]);
        $exists = $select->fetch(PDO::FETCH_ASSOC) !== false;

        if (!$exists) {
            $columns = array_keys($values);
            $list = '`' . implode('`, `', $columns) . '`';
            $placeholders = implode(', ', array_fill(0, count($columns), '?'));
            $this->db->prepare("INSERT INTO titles ($list) VALUES ($placeholders)")
                     ->execute(array_values($values));
            return true;
        }

        $set = implode(', ', array_map(
            fn (string $field): string => "`$field` = ?",
            self::FIELDS
        ));
        $params = array_map(fn (string $field): mixed => $values[$field], self::FIELDS);
        $params[] = $values['metadata_updated_at'];
        $params[] = self::SOURCE_TMDB;
        $params[] = $values['refreshed_at'];
        $params[] = $tmdbId;
        $params[] = $isTv;
        $params[] = $locale;
        $this->db->prepare(
            "UPDATE titles SET $set, metadata_updated_at = ?, source = ?, refreshed_at = ?
             WHERE tmdb_id = ? AND is_tv = ? AND locale = ?"
        )->execute($params);
        return true;
    }

    /**
     * Tek bir alanı depolanabilir hâle getirir. Client ve TMDB yolları aynı
     * normalizasyondan geçer: kanonik kaynak da bozuk değer dönebilir ve iki
     * ayrı kural kümesi zamanla birbirinden ayrışır.
     */
    private function normalizeField(string $field, mixed $incoming): mixed
    {
        if ($field === 'genre_ids') {
            if ($incoming === null || $incoming === '') {
                return null;
            }
            return is_string($incoming)
                ? $incoming
                : json_encode($incoming, JSON_UNESCAPED_UNICODE);
        }
        if (in_array($field, self::IMAGE_PATH_FIELDS, true)) {
            return self::sanitizeImagePath($incoming);
        }
        if (isset(self::TEXT_LIMITS[$field])) {
            return sanitize_title_text(
                is_string($incoming) || $incoming === null ? $incoming : (string) $incoming,
                self::TEXT_LIMITS[$field]
            );
        }
        return match ($field) {
            'vote_average' => self::clampNumber($incoming, 0.0, self::VOTE_AVERAGE_MAX),
            'popularity' => self::clampNumber($incoming, 0.0, self::POPULARITY_MAX),
            'release_date' => self::sanitizeDate($incoming),
            default => $incoming,
        };
    }

    /**
     * TMDB göreli görsel yolu. `..` içeren değerler reddedilir: karakter sınıfı
     * hem `.` hem `/` içerdiği için desen tek başına `/../../x.jpg`'yi kabul eder.
     */
    private static function sanitizeImagePath(mixed $path): ?string
    {
        if (!is_string($path) || $path === '') {
            return null;
        }
        if (str_contains($path, '..')) {
            return null;
        }
        return preg_match('#^/[A-Za-z0-9._/-]+$#', $path) === 1 ? $path : null;
    }

    /** Sayısal olmayan veya sonsuz değerler düşer; geri kalanı aralığa sıkışır. */
    private static function clampNumber(mixed $value, float $min, float $max): ?float
    {
        if ($value === null || $value === '' || is_bool($value)) {
            return null;
        }
        if (!is_int($value) && !is_float($value) && !(is_string($value) && is_numeric($value))) {
            return null;
        }
        $number = (float) $value;
        if (!is_finite($number)) {
            return null;
        }
        return max($min, min($max, $number));
    }

    /** Yalnız YYYY-AA-GG kabul edilir; TMDB yayınlanmamış yapımlar için '' döner. */
    private static function sanitizeDate(mixed $value): ?string
    {
        if (!is_string($value) || $value === '') {
            return null;
        }
        return preg_match('/^\d{4}-\d{2}-\d{2}$/', $value) === 1 ? $value : null;
    }

    private function refreshOne(int $tmdbId, int $isTv, string $locale, ?int $nowMs = null): bool
    {
        if ($this->tmdb === null) {
            return false;
        }
        $nowMs ??= (int) round(microtime(true) * 1000);
        try {
            $data = $this->tmdb->fetchDetails($tmdbId, $isTv === 1, $locale);
        } catch (Throwable $e) {
            if (function_exists('cinema_error')) {
                cinema_error('TitleCatalog TMDB refresh failed: ' . $e->getMessage());
            }
            return false;
        }
        if ($data === null) {
            return false;
        }
        return $this->applyTmdb($tmdbId, $isTv, $locale, $data, $nowMs);
    }
}
