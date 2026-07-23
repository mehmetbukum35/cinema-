<?php
declare(strict_types=1);
// Senkronizasyon: GET /sync (çekme) + POST /sync (itme), last-write-wins.
// Ayrıca nadir/tekil işlem için klasik uç örneği: DELETE /search-history (tümünü temizle).

class Sync
{
    // Her tablonun anahtar kolonları + senkronlanan veri kolonları + JSON kolonları.
    private const TABLES = [
        'ratings' => [
            'keys' => ['movie_id', 'is_tv'],
            'cols' => ['rating', 'created_at', 'comment', 'is_spoiler', 'is_private'],
            'json' => [],
            'title_key' => 'movie_id',
        ],
        'watchlist' => [
            'keys' => ['id', 'is_tv'],
            'cols' => ['created_at'],
            'json' => [],
            'title_key' => 'id',
        ],
        'favorites' => [
            'keys' => ['id', 'is_tv'],
            'cols' => ['created_at'],
            'json' => [],
            'title_key' => 'id',
        ],
        'watched_seasons' => [
            'keys' => ['tv_id', 'season_number'],
            'cols' => [],
            'json' => [],
        ],
        'search_history' => [
            'keys' => ['query'],
            'cols' => ['created_at'],
            'json' => [],
        ],
    ];

    public function __construct(private PDO $db) {}

    private function acknowledgeDevice(
        int $uid,
        ?string $deviceId,
        int $ackCursor,
        bool $required,
        bool $localReset = false
    ): void {
        $deviceId = trim((string) $deviceId);
        if ($deviceId === '' && !$required) return;
        if (!preg_match('/^[A-Za-z0-9_-]{16,64}$/', $deviceId)) {
            fail(422, 'Geçerli device_id gerekli.', 'sync_device_required');
        }
        $ackCursor = max(0, $ackCursor);
        $now = now_ms();

        $st = $this->db->prepare(
            'SELECT last_ack_cursor, invalidated_at FROM sync_devices
             WHERE user_id = ? AND device_id = ?'
        );
        $st->execute([$uid, $deviceId]);
        $device = $st->fetch();

        if ($device !== false) {
            $wasInvalidated = $device['invalidated_at'] !== null;
            // Invalidated devices always require an explicit local wipe + local_reset.
            if ($wasInvalidated && !$localReset) {
                fail(409, 'Bu cihaz tam yeniden senkronizasyon gerektiriyor.', 'sync_reset_required');
            }
            $nextAck = $wasInvalidated
                ? 0
                : max((int) $device['last_ack_cursor'], $ackCursor);
            $up = $this->db->prepare(
                'UPDATE sync_devices
                 SET last_ack_cursor = ?, last_seen_at = ?, invalidated_at = NULL
                 WHERE user_id = ? AND device_id = ?'
            );
            $up->execute([$nextAck, $now, $uid, $deviceId]);
            return;
        }

        $gc = $this->db->prepare('SELECT gc_cursor FROM sync_gc_state WHERE user_id = ?');
        $gc->execute([$uid]);
        if ((int) ($gc->fetchColumn() ?: 0) > 0 && $ackCursor > 0) {
            fail(409, 'Bu cihaz tam yeniden senkronizasyon gerektiriyor.', 'sync_reset_required');
        }

        $insert = $this->db->prepare(
            'INSERT INTO sync_devices
             (user_id, device_id, last_ack_cursor, last_seen_at, created_at, invalidated_at)
             VALUES (?, ?, ?, ?, ?, NULL)'
        );
        $insert->execute([$uid, $deviceId, $ackCursor, $now, $now]);
    }

    /** Push başına kullanıcı yasağı bir kez okunur (upsert kayıt başına çağrılır). */
    private array $reviewBanCache = [];

    private function isReviewBanned(int $uid): bool
    {
        if (!array_key_exists($uid, $this->reviewBanCache)) {
            $st = $this->db->prepare('SELECT review_banned FROM users WHERE id = ?');
            $st->execute([$uid]);
            $this->reviewBanCache[$uid] = ((int) $st->fetchColumn()) === 1;
        }
        return $this->reviewBanCache[$uid];
    }

    // ─── GET /sync?since=<unix_ms> ──────────────────────────────────────────
    // since'ten sonra değişen tüm kayıtları (silmeler dahil) döner.
    public function pull(
        int $uid,
        int $since,
        ?string $locale = null,
        ?string $deviceId = null,
        int $ackCursor = 0,
        bool $requireDevice = false,
        bool $localReset = false
    ): void
    {
        $this->acknowledgeDevice($uid, $deviceId, $ackCursor, $requireDevice, $localReset);
        $locale = cinema_content_locale($locale);
        $out = ['server_time' => now_ms()];
        foreach (self::TABLES as $table => $def) {
            $select = "SELECT d.*";
            $join = '';
            if (isset($def['title_key'])) {
                $select .= ', COALESCE(t.locale, tf.locale) AS metadata_locale,
                            COALESCE(t.title, tf.title) AS title,
                            COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                            COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                            COALESCE(t.overview, tf.overview) AS overview,
                            COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                            COALESCE(t.release_date, tf.release_date) AS release_date,
                            COALESCE(t.popularity, tf.popularity) AS popularity,
                            COALESCE(t.genre_ids, tf.genre_ids) AS genre_ids';
                $join = " LEFT JOIN titles t ON t.tmdb_id = d.`{$def['title_key']}`
                          AND t.is_tv = d.is_tv AND t.locale = ?
                          LEFT JOIN titles tf ON tf.tmdb_id = d.`{$def['title_key']}`
                          AND tf.is_tv = d.is_tv AND tf.locale = 'und'";
            }
            // Pull imleci (`since`) SUNUCU saatiyle ilerler; bu yüzden filtre de
            // sunucu-otoriter `server_updated_at` kolonuna bakar. Cihaz saatli
            // `updated_at` ile filtrelenirse, saati geride bir cihazın yazdıkları
            // başka cihazların cursor'unun altında kalıp kalıcı olarak atlanırdı.
            $st = $this->db->prepare(
                "$select FROM `$table` d$join
                 WHERE d.user_id = ? AND d.server_updated_at > ? ORDER BY d.updated_at ASC"
            );
            $params = isset($def['title_key']) ? [$locale, $uid, $since] : [$uid, $since];
            $st->execute($params);
            $rows = [];
            foreach ($st->fetchAll() as $r) {
                unset($r['user_id'], $r['server_updated_at']);
                foreach (array_unique(array_merge($def['json'], isset($def['title_key']) ? ['genre_ids'] : [])) as $jc) {
                    if (isset($r[$jc])) $r[$jc] = json_decode($r[$jc], true);
                }
                $r['deleted'] = ((int) $r['deleted']) !== 0;
                $rows[] = $r;
            }
            $out[$table] = $rows;
        }
        json_out(200, $out);
    }

    // ─── POST /sync ─────────────────────────────────────────────────────────
    // İstemcideki değişiklikleri uygular. Çakışma: en yüksek updated_at kazanır.
    // Tek istekte tablo başına kabul edilen azami kayıt. Meşru delta sync'ler
    // bunun çok altında kalır; sınır, kimlikli bir istemcinin depoyu sınırsız
    // şişirmesini ve upsert döngüsünün transaction'ı kilitlemesini önler.
    private const MAX_ITEMS_PER_TABLE = 500;

    public function push(int $uid, array $in, bool $requireDevice = false): void
    {
        $this->acknowledgeDevice(
            $uid,
            isset($in['device_id']) ? (string) $in['device_id'] : null,
            (int) ($in['ack_cursor'] ?? 0),
            $requireDevice,
            !empty($in['local_reset'])
        );
        $locale = self::metadataLocale($in['metadata_locale'] ?? null);
        // Sınır kontrolü transaction'a girmeden yapılır.
        foreach (self::TABLES as $table => $def) {
            $items = $in[$table] ?? null;
            if (is_array($items) && count($items) > self::MAX_ITEMS_PER_TABLE) {
                fail(413, "Çok fazla kayıt: $table (tek istekte en fazla " . self::MAX_ITEMS_PER_TABLE . ').');
            }
        }

        $applied = 0;
        $this->db->beginTransaction();
        try {
            foreach (self::TABLES as $table => $def) {
                $items = $in[$table] ?? null;
                if (!is_array($items)) continue;
                foreach ($items as $item) {
                    if (!is_array($item)) continue;
                    $applied += $this->upsert($uid, $table, $def, $item, $locale) ? 1 : 0;
                }
            }
            $this->db->commit();
        } catch (Throwable $e) {
            $this->db->rollBack();
            cinema_error('Sync push failed: ' . $e->getMessage(), $uid);
            fail(500, 'Senkronizasyon uygulanamadı.');
        }
        json_out(200, ['server_time' => now_ms(), 'applied' => $applied]);
    }

    // ─── DELETE /search-history (klasik tekil uç örneği) ────────────────────
    public function clearSearchHistory(int $uid): void
    {
        // Soft delete: senkronizasyonun diğer cihazlara da yansıması için.
        // Pull `server_updated_at > since` ile filtreler — updated_at tek başına yetmez.
        $now = now_ms();
        $st = $this->db->prepare(
            'UPDATE search_history SET deleted = 1, updated_at = ?, server_updated_at = ?
             WHERE user_id = ? AND deleted = 0'
        );
        $st->execute([$now, $now, $uid]);
        json_out(200, ['ok' => true, 'cleared' => $st->rowCount()]);
    }

    // ─── DELETE /sync (Tüm senkronizasyon verilerini temizle) ────────────────
    public function resetAllData(int $uid): void
    {
        $now = now_ms();
        $this->db->beginTransaction();
        try {
            foreach (self::TABLES as $table => $def) {
                $st = $this->db->prepare(
                    "UPDATE `$table` SET deleted = 1, updated_at = ?, server_updated_at = ?
                     WHERE user_id = ? AND deleted = 0"
                );
                $st->execute([$now, $now, $uid]);
            }
            // Diğer cihazlar tombstone'ları kaçırmasın diye tam yeniden çekmeye zorla.
            $inv = $this->db->prepare(
                'UPDATE sync_devices SET invalidated_at = ?
                 WHERE user_id = ? AND invalidated_at IS NULL'
            );
            $inv->execute([$now, $uid]);
            $this->db->commit();
            json_out(200, ['ok' => true]);
        } catch (Throwable $e) {
            $this->db->rollBack();
            cinema_error('Sync reset failed: ' . $e->getMessage(), $uid);
            fail(500, 'Veriler sunucudan temizlenemedi.');
        }
    }

    // ─── Tek kaydı upsert et (last-write-wins) ──────────────────────────────
    // Motor-bağımsız "önce kontrol et, sonra yaz" deseni: hem MySQL/MariaDB hem
    // SQLite'ta çalışır (MySQL'e özgü `ON DUPLICATE KEY UPDATE` kullanılmaz).
    // Dönüş: kayıt yazıldı/güncellendiyse true; gelen veri eski olduğu için
    // yok sayıldıysa false (böylece `applied` sayacı gerçekten uygulananları sayar).
    private function upsert(int $uid, string $table, array $def, array $item, string $locale): bool
    {
        // Anahtarlar zorunlu
        foreach ($def['keys'] as $k) {
            if (!array_key_exists($k, $item)) return false;
        }

        // Puanlama doğrulaması: 0-3 arası olmalı
        if ($table === 'ratings' && empty($item['deleted'])) {
            if (!isset($item['rating']) || (int)$item['rating'] < 0 || (int)$item['rating'] > 3) {
                return false;
            }
        }

        // Yorum doğrulaması: istemcinin 280 sınırına güvenilmez — kırp, URL'leri
        // sök, kontrol karakterlerini temizle (bkz. sanitize_comment).
        if ($table === 'ratings' && array_key_exists('comment', $item)) {
            $item['comment'] = sanitize_comment(
                is_string($item['comment']) ? $item['comment'] : null
            );
        }
        // İstemci saati ileri kaçmışsa LWW / titles metadata sonsuza kilitlenmesin.
        $serverNow = now_ms();
        $skewMs = 5 * 60 * 1000; // 5 dk tolerans
        $updatedAt = (int) ($item['updated_at'] ?? $serverNow);
        if ($updatedAt > $serverNow + $skewMs) {
            $updatedAt = $serverNow;
        }
        if ($updatedAt < 0) {
            $updatedAt = $serverNow;
        }
        $deleted   = !empty($item['deleted']) ? 1 : 0;

        if (isset($def['title_key']) && !$deleted) {
            $itemLocale = self::metadataLocale($item['metadata_locale'] ?? $locale);
            $this->upsertTitle($item, (string) $def['title_key'], $updatedAt, $itemLocale);
        }

        // Anahtara göre WHERE (user_id + tablo anahtarları) — her iki motorda aynı.
        $whereParts = ['`user_id` = ?'];
        $whereVals  = [$uid];
        foreach ($def['keys'] as $k) {
            $whereParts[] = "`$k` = ?";
            $whereVals[]  = $item[$k];
        }
        $whereSql = implode(' AND ', $whereParts);

        // Mevcut kaydı oku (varsa).
        $sel = $this->db->prepare("SELECT * FROM `$table` WHERE $whereSql");
        $sel->execute($whereVals);
        $existing = $sel->fetch(PDO::FETCH_ASSOC);

        if ($existing !== false && $updatedAt < (int) $existing['updated_at']) {
            return false;
        }

        $allCols = array_merge($def['keys'], $def['cols'], ['updated_at', 'deleted']);
        $values  = ['user_id' => $uid];
        foreach ($allCols as $c) {
            if ($c === 'updated_at') { $values[$c] = $updatedAt; continue; }
            if ($c === 'deleted')    { $values[$c] = $deleted;   continue; }
            if ($existing !== false && !array_key_exists($c, $item)) {
                $values[$c] = $existing[$c];
                continue;
            }
            $v = $item[$c] ?? null;
            if (($c === 'is_spoiler' || $c === 'is_private') && $v === null) {
                $v = 0;
            }
            if (in_array($c, $def['json'], true) && $v !== null) {
                $v = json_encode($v, JSON_UNESCAPED_UNICODE);
            }
            $values[$c] = $v;
        }
        // created_at yoksa (yeni kayıt) updated_at ile doldur.
        if (in_array('created_at', $def['cols'], true) && ($values['created_at'] ?? null) === null) {
            $values['created_at'] = $updatedAt;
        }

        // Küfür/spam tespiti: işaretli yorum sunucuda gizlenir. is_hidden sync
        // kolonu DEĞİLDİR — kullanıcının kendi verisi bozulmaz, yorum yalnızca
        // başkalarına gösterilmez. Yorum metni değiştiğinde yeniden değerlendirilir:
        // küfrü temizleyen kullanıcı otomatik görünür olur; buna karşılık şikayet
        // yoluyla gizlenmiş bir yorum ancak metin değişirse görünürlüğe döner.
        $extraCols = [];
        if ($table === 'ratings') {
            $newComment = $values['comment'] ?? null;
            $oldComment = $existing !== false ? ($existing['comment'] ?? null) : null;
            if ($existing === false || $newComment !== $oldComment) {
                // Küfür filtresi VEYA yorum yasağı (susturulmuş kullanıcı):
                // ikisi de yeni/değişen yorumu başkalarından gizler.
                $extraCols['is_hidden'] =
                    ($newComment !== null &&
                        (comment_flagged((string) $newComment) || $this->isReviewBanned($uid)))
                    ? 1 : 0;
            }
        }
        $values = array_merge($values, $extraCols);

        // Sunucu-otoriter senkron imleci: YALNIZ satır gerçekten ilerlediğinde
        // (yeni kayıt ya da kesinlikle daha yeni updated_at) sunucu saatiyle
        // damgalanır. Aynı updated_at'li idempotent bir re-push bunu "now"a
        // çekseydi, satır gönderen cihaza geri pull'lanır ve SONSUZ sync döngüsü
        // oluşurdu: aynı updated_at'li satırlar 1ms örtüşme (_overlappingCursor)
        // yüzünden her turda yeniden push edilir; her push server_updated_at'i
        // ilerletseydi pull onları sürekli geri döndürürdü. Çakışma çözümü
        // (hangi satır kazanır) yine client updated_at'iyle yapılır.
        $serverNow = now_ms();
        $bumpServerCursor =
            $existing === false || $updatedAt > (int) $existing['updated_at'];

        if ($existing === false) {
            // Yeni kayıt → INSERT
            $values['server_updated_at'] = $serverNow;
            $colNames = array_keys($values);
            $place    = implode(', ', array_fill(0, count($colNames), '?'));
            $colList  = '`' . implode('`, `', $colNames) . '`';
            $this->db->prepare("INSERT INTO `$table` ($colList) VALUES ($place)")
                     ->execute(array_values($values));
            return true;
        }

        // Eşit/yeni → anahtar dışındaki tüm kolonları güncelle.
        $updateCols = array_merge($def['cols'], ['updated_at', 'deleted'], array_keys($extraCols));
        $setParts = [];
        $setVals  = [];
        foreach ($updateCols as $c) {
            $setParts[] = "`$c` = ?";
            $setVals[]  = $values[$c];
        }
        if ($bumpServerCursor) {
            $setParts[] = '`server_updated_at` = ?';
            $setVals[]  = $serverNow;
        }
        $this->db->prepare("UPDATE `$table` SET " . implode(', ', $setParts) . " WHERE $whereSql")
                 ->execute(array_merge($setVals, $whereVals));
        return true;
    }

    /** Store shared TMDB metadata once; stale clients cannot overwrite newer data. */
    private function upsertTitle(array $item, string $idKey, int $updatedAt, string $locale): void
    {
        $tmdbId = (int) ($item[$idKey] ?? 0);
        if ($tmdbId <= 0) return;
        $isTv = !empty($item['is_tv']) ? 1 : 0;

        // TMDB image paths must be root-relative and charset-safe (no URL injection).
        foreach (['poster_path', 'backdrop_path'] as $pathField) {
            if (!array_key_exists($pathField, $item)) continue;
            $path = $item[$pathField];
            if ($path === null || $path === '') continue;
            if (!is_string($path) || !preg_match('#^/[A-Za-z0-9._/-]+$#', $path)) {
                $item[$pathField] = null;
            }
        }

        $fields = [
            'title', 'poster_path', 'backdrop_path', 'overview', 'vote_average',
            'release_date', 'popularity', 'genre_ids',
        ];
        $hasMetadata = false;
        foreach ($fields as $field) {
            if (array_key_exists($field, $item) && $item[$field] !== null && $item[$field] !== '') {
                $hasMetadata = true;
                break;
            }
        }
        if (!$hasMetadata) return;

        $select = $this->db->prepare('SELECT * FROM titles WHERE tmdb_id = ? AND is_tv = ? AND locale = ?');
        $select->execute([$tmdbId, $isTv, $locale]);
        $existing = $select->fetch(PDO::FETCH_ASSOC);
        if ($existing !== false && $updatedAt < (int) $existing['metadata_updated_at']) return;

        $values = ['tmdb_id' => $tmdbId, 'is_tv' => $isTv, 'locale' => $locale];
        foreach ($fields as $field) {
            $incoming = $item[$field] ?? null;
            if ($field === 'genre_ids' && $incoming !== null && !is_string($incoming)) {
                $incoming = json_encode($incoming, JSON_UNESCAPED_UNICODE);
            }
            $values[$field] = ($incoming === null || $incoming === '') && $existing !== false
                ? $existing[$field]
                : $incoming;
        }
        $values['metadata_updated_at'] = max($updatedAt, (int) ($existing['metadata_updated_at'] ?? 0));

        if ($existing === false) {
            $columns = array_keys($values);
            $list = '`' . implode('`, `', $columns) . '`';
            $placeholders = implode(', ', array_fill(0, count($columns), '?'));
            $this->db->prepare("INSERT INTO titles ($list) VALUES ($placeholders)")
                     ->execute(array_values($values));
            return;
        }
        $set = implode(', ', array_map(fn (string $field): string => "`$field` = ?", array_slice($fields, 0)));
        $params = array_map(fn (string $field): mixed => $values[$field], $fields);
        $params[] = $values['metadata_updated_at'];
        $params[] = $tmdbId;
        $params[] = $isTv;
        $params[] = $locale;
        $this->db->prepare("UPDATE titles SET $set, metadata_updated_at = ? WHERE tmdb_id = ? AND is_tv = ? AND locale = ?")
                 ->execute($params);
    }

    private static function metadataLocale(mixed $value): string
    {
        $locale = strtolower(trim((string) $value));
        return in_array($locale, ['tr', 'en'], true) ? $locale : 'und';
    }
}
