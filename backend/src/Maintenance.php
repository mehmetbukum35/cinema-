<?php
declare(strict_types=1);

/**
 * Bounded, idempotent database housekeeping for shared hosting.
 *
 * Sync tombstones are deleted only after the retention window and after every
 * active device has acknowledged their cursor. Dormant devices are invalidated
 * and must perform a full pull before they can push again.
 */
final class Maintenance
{
    private const DEFAULTS = [
        'batch_limit' => 500,
        'search_history_limit' => 50,
        'couch_open_hours' => 24,
        'couch_cancelled_days' => 7,
        'couch_terminal_days' => 30,
        'tombstone_retention_days' => 30,
        'sync_device_inactive_days' => 90,
    ];

    private array $options;

    public function __construct(private PDO $db, array $options = [])
    {
        $this->options = array_replace(self::DEFAULTS, $options);
        $this->options['batch_limit'] = max(1, min(5000, (int) $this->options['batch_limit']));
        $this->options['search_history_limit'] = max(0, min(500, (int) $this->options['search_history_limit']));
        $this->options['tombstone_retention_days'] = max(7, min(365, (int) $this->options['tombstone_retention_days']));
        $this->options['sync_device_inactive_days'] = max(30, min(730, (int) $this->options['sync_device_inactive_days']));
    }

    /** @return array<string, int> affected row counts */
    public function run(?int $nowMs = null): array
    {
        $nowMs ??= (int) round(microtime(true) * 1000);
        $result = [];

        $this->db->beginTransaction();
        try {
            $result['search_history_tombstoned'] = $this->capSearchHistory($nowMs);
            $result['sync_devices_invalidated'] = $this->invalidateInactiveSyncDevices($nowMs);
            $result['ratings_tombstones_compacted'] = 0;
            $result['watchlist_tombstones_compacted'] = 0;
            $result['favorites_tombstones_compacted'] = 0;
            $tombstoneCutoff = $nowMs - ((int) $this->options['tombstone_retention_days'] * 86400000);
            $result['ratings_tombstones_deleted'] = $this->deleteAcknowledgedTombstones(
                'ratings', ['movie_id', 'is_tv'], $tombstoneCutoff, $nowMs
            );
            $result['watchlist_tombstones_deleted'] = $this->deleteAcknowledgedTombstones(
                'watchlist', ['id', 'is_tv'], $tombstoneCutoff, $nowMs
            );
            $result['favorites_tombstones_deleted'] = $this->deleteAcknowledgedTombstones(
                'favorites', ['id', 'is_tv'], $tombstoneCutoff, $nowMs
            );
            $result['watched_seasons_tombstones_deleted'] = $this->deleteAcknowledgedTombstones(
                'watched_seasons', ['tv_id', 'season_number'], $tombstoneCutoff, $nowMs
            );
            $result['search_history_tombstones_deleted'] = $this->deleteAcknowledgedTombstones(
                'search_history', ['query'], $tombstoneCutoff, $nowMs
            );
            $result['couch_sessions_expired'] = $this->expireOpenCouchSessions($nowMs);
            $result['couch_sessions_deleted'] = $this->deleteOldCouchSessions($nowMs);
            $result['refresh_tokens_deleted'] = $this->deleteExpired('refresh_tokens', 'expires_at', intdiv($nowMs, 1000));
            $result['password_resets_deleted'] = $this->deleteExpired('password_resets', 'expires_at', $nowMs);
            $result['email_verifications_deleted'] = $this->deleteExpired('email_verifications', 'expires_at', $nowMs);
            $result['rate_limits_deleted'] = $this->deleteExpired('rate_limits', 'window_time', intdiv($nowMs, 1000) - 120);
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }

        return $result;
    }

    private function invalidateInactiveSyncDevices(int $nowMs): int
    {
        $cutoff = $nowMs - ((int) $this->options['sync_device_inactive_days'] * 86400000);
        $st = $this->db->prepare(
            'UPDATE sync_devices SET invalidated_at = ?
             WHERE invalidated_at IS NULL AND last_seen_at < ?'
        );
        $st->execute([$nowMs, $cutoff]);
        return $st->rowCount();
    }

    private function deleteAcknowledgedTombstones(
        string $table,
        array $keys,
        int $cutoff,
        int $nowMs
    ): int {
        $allowed = [
            'ratings' => ['movie_id', 'is_tv'],
            'watchlist' => ['id', 'is_tv'],
            'favorites' => ['id', 'is_tv'],
            'watched_seasons' => ['tv_id', 'season_number'],
            'search_history' => ['query'],
        ];
        if (($allowed[$table] ?? null) !== $keys) {
            throw new InvalidArgumentException('Unsupported tombstone table.');
        }

        $columns = implode(', ', array_map(fn (string $key): string => "d.`$key`", $keys));
        $select = $this->db->prepare(
            "SELECT d.user_id, $columns, d.updated_at
             FROM `$table` d
             WHERE d.deleted = 1 AND d.updated_at < ?
               AND NOT EXISTS (
                 SELECT 1 FROM sync_devices sd
                 WHERE sd.user_id = d.user_id
                   AND sd.invalidated_at IS NULL
                   AND sd.last_ack_cursor < d.updated_at
               )
             ORDER BY d.updated_at ASC
             LIMIT " . (int) $this->options['batch_limit']
        );
        $select->execute([$cutoff]);
        $rows = $select->fetchAll(PDO::FETCH_ASSOC);
        if ($rows === []) return 0;

        $where = implode(' AND ', array_map(fn (string $key): string => "`$key` = ?", $keys));
        $delete = $this->db->prepare(
            "DELETE FROM `$table` WHERE user_id = ? AND $where AND deleted = 1"
        );
        $gcByUser = [];
        $changed = 0;
        foreach ($rows as $row) {
            $params = [(int) $row['user_id']];
            foreach ($keys as $key) $params[] = $row[$key];
            $delete->execute($params);
            $changed += $delete->rowCount();
            $uid = (int) $row['user_id'];
            $gcByUser[$uid] = max($gcByUser[$uid] ?? 0, (int) $row['updated_at']);
        }

        $findGc = $this->db->prepare('SELECT gc_cursor FROM sync_gc_state WHERE user_id = ?');
        $insertGc = $this->db->prepare(
            'INSERT INTO sync_gc_state (user_id, gc_cursor, updated_at) VALUES (?, ?, ?)'
        );
        $updateGc = $this->db->prepare(
            'UPDATE sync_gc_state SET gc_cursor = ?, updated_at = ? WHERE user_id = ?'
        );
        foreach ($gcByUser as $uid => $cursor) {
            $findGc->execute([$uid]);
            $existing = $findGc->fetchColumn();
            if ($existing === false) {
                $insertGc->execute([$uid, $cursor, $nowMs]);
            } elseif ($cursor > (int) $existing) {
                $updateGc->execute([$cursor, $nowMs, $uid]);
            }
        }
        return $changed;
    }

    private function capSearchHistory(int $nowMs): int
    {
        $limit = $this->options['search_history_limit'];
        $batch = $this->options['batch_limit'];
        $users = $this->db->query(
            'SELECT user_id FROM search_history WHERE deleted = 0
             GROUP BY user_id HAVING COUNT(*) > ' . (int) $limit . '
             ORDER BY user_id LIMIT ' . (int) $batch
        )->fetchAll(PDO::FETCH_COLUMN);

        $changed = 0;
        $select = $this->db->prepare(
            'SELECT query FROM search_history
             WHERE user_id = ? AND deleted = 0
             ORDER BY updated_at DESC, query ASC
             LIMIT ' . (int) $batch . ' OFFSET ' . (int) $limit
        );
        $update = $this->db->prepare(
            'UPDATE search_history SET deleted = 1, updated_at = ?
             WHERE user_id = ? AND query = ? AND deleted = 0'
        );
        foreach ($users as $userId) {
            $select->execute([(int) $userId]);
            foreach ($select->fetchAll(PDO::FETCH_COLUMN) as $query) {
                $update->execute([$nowMs, (int) $userId, $query]);
                $changed += $update->rowCount();
            }
        }
        return $changed;
    }

    private function expireOpenCouchSessions(int $nowMs): int
    {
        $cutoff = $nowMs - ((int) $this->options['couch_open_hours'] * 3600000);
        $ids = $this->selectIds('couch_sessions', "status IN ('pending', 'active') AND updated_at < ?", [$cutoff]);
        $st = $this->db->prepare("UPDATE couch_sessions SET status = 'cancelled', updated_at = ? WHERE id = ?");
        $changed = 0;
        foreach ($ids as $id) {
            $st->execute([$nowMs, $id]);
            $changed += $st->rowCount();
        }
        return $changed;
    }

    private function deleteOldCouchSessions(int $nowMs): int
    {
        $cancelledCutoff = $nowMs - ((int) $this->options['couch_cancelled_days'] * 86400000);
        $terminalCutoff = $nowMs - ((int) $this->options['couch_terminal_days'] * 86400000);
        $ids = $this->selectIds(
            'couch_sessions',
            "(status = 'cancelled' AND updated_at < ?) OR
             (status IN ('ended', 'matched') AND updated_at < ?)",
            [$cancelledCutoff, $terminalCutoff]
        );
        $st = $this->db->prepare('DELETE FROM couch_sessions WHERE id = ?');
        $changed = 0;
        foreach ($ids as $id) {
            $st->execute([$id]);
            $changed += $st->rowCount();
        }
        return $changed;
    }

    private function deleteExpired(string $table, string $column, int $cutoff): int
    {
        $allowed = [
            'refresh_tokens' => ['column' => 'expires_at', 'keys' => ['id']],
            'password_resets' => ['column' => 'expires_at', 'keys' => ['email']],
            'email_verifications' => ['column' => 'expires_at', 'keys' => ['email']],
            'rate_limits' => ['column' => 'window_time', 'keys' => ['ip_bucket', 'window_time']],
        ];
        $definition = $allowed[$table] ?? null;
        if ($definition === null || $definition['column'] !== $column) {
            throw new InvalidArgumentException('Unsupported expiry table.');
        }
        $keys = $this->selectCompositeKeys(
            $table,
            $definition['keys'],
            "`$column` < ?",
            [$cutoff]
        );
        $where = implode(' AND ', array_map(fn (string $key): string => "`$key` = ?", $definition['keys']));
        $st = $this->db->prepare("DELETE FROM `$table` WHERE $where");
        return $this->applyCompositeKeys($st, $keys);
    }

    /** @return list<int> */
    private function selectIds(string $table, string $where, array $params): array
    {
        $st = $this->db->prepare(
            "SELECT id FROM `$table` WHERE $where ORDER BY id LIMIT " . (int) $this->options['batch_limit']
        );
        $st->execute($params);
        return array_map('intval', $st->fetchAll(PDO::FETCH_COLUMN));
    }

    /** @return list<array<string, mixed>> */
    private function selectCompositeKeys(string $table, array $columns, string $where, array $params): array
    {
        $columnList = implode(', ', array_map(fn (string $column): string => "`$column`", $columns));
        $st = $this->db->prepare(
            "SELECT $columnList FROM `$table` WHERE $where LIMIT " . (int) $this->options['batch_limit']
        );
        $st->execute($params);
        return $st->fetchAll(PDO::FETCH_ASSOC);
    }

    private function applyCompositeKeys(PDOStatement $statement, array $rows): int
    {
        $changed = 0;
        foreach ($rows as $row) {
            $statement->execute(array_values($row));
            $changed += $statement->rowCount();
        }
        return $changed;
    }
}
