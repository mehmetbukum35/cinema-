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

        foreach (['poster_path', 'backdrop_path'] as $pathField) {
            if (!array_key_exists($pathField, $item)) {
                continue;
            }
            $path = $item[$pathField];
            if ($path === null || $path === '') {
                continue;
            }
            if (!is_string($path) || !preg_match('#^/[A-Za-z0-9._/-]+$#', $path)) {
                $item[$pathField] = null;
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
            $incoming = $item[$field] ?? null;
            if ($field === 'genre_ids' && $incoming !== null && !is_string($incoming)) {
                $incoming = json_encode($incoming, JSON_UNESCAPED_UNICODE);
            }
            if (isset(self::TEXT_LIMITS[$field])) {
                $incoming = sanitize_title_text(
                    is_string($incoming) || $incoming === null ? $incoming : (string) $incoming,
                    self::TEXT_LIMITS[$field]
                );
            }
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
        foreach ($this->pendingRefresh as $item) {
            if ($count >= $max) {
                break;
            }
            if ($this->refreshOne($item['tmdb_id'], $item['is_tv'], $item['locale'])) {
                $count++;
            }
        }
        $this->pendingRefresh = [];
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
            $incoming = $fields[$field] ?? null;
            if ($field === 'genre_ids' && $incoming !== null && !is_string($incoming)) {
                $incoming = json_encode($incoming, JSON_UNESCAPED_UNICODE);
            }
            if (in_array($field, ['poster_path', 'backdrop_path'], true)) {
                if ($incoming !== null && $incoming !== '') {
                    if (!is_string($incoming) || !preg_match('#^/[A-Za-z0-9._/-]+$#', $incoming)) {
                        $incoming = null;
                    }
                }
            }
            if (isset(self::TEXT_LIMITS[$field])) {
                $incoming = sanitize_title_text(
                    is_string($incoming) || $incoming === null ? $incoming : (string) $incoming,
                    self::TEXT_LIMITS[$field]
                );
            }
            $values[$field] = $incoming;
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
