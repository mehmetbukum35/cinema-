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
            'cols' => ['rating', 'genre_ids', 'title', 'poster_path', 'backdrop_path',
                       'overview', 'vote_average', 'release_date', 'popularity', 'created_at',
                       'comment', 'is_spoiler'],
            'json' => ['genre_ids'],
        ],
        'watchlist' => [
            'keys' => ['id', 'is_tv'],
            'cols' => ['title', 'poster_path', 'backdrop_path', 'overview',
                       'vote_average', 'release_date', 'genre_ids', 'created_at'],
            'json' => ['genre_ids'],
        ],
        'favorites' => [
            'keys' => ['id', 'is_tv'],
            'cols' => ['title', 'poster_path', 'backdrop_path', 'overview',
                       'vote_average', 'release_date', 'genre_ids', 'created_at'],
            'json' => ['genre_ids'],
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

    // ─── GET /sync?since=<unix_ms> ──────────────────────────────────────────
    // since'ten sonra değişen tüm kayıtları (silmeler dahil) döner.
    public function pull(int $uid, int $since): void
    {
        $out = ['server_time' => now_ms()];
        foreach (self::TABLES as $table => $def) {
            $st = $this->db->prepare(
                "SELECT * FROM `$table` WHERE user_id = ? AND updated_at > ? ORDER BY updated_at ASC"
            );
            $st->execute([$uid, $since]);
            $rows = [];
            foreach ($st->fetchAll() as $r) {
                unset($r['user_id']);
                foreach ($def['json'] as $jc) {
                    if (isset($r[$jc])) $r[$jc] = json_decode($r[$jc], true);
                }
                $r['deleted'] = (bool) $r['deleted'];
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
    private const MAX_ITEMS_PER_TABLE = 10000;

    public function push(int $uid, array $in): void
    {
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
                    $applied += $this->upsert($uid, $table, $def, $item) ? 1 : 0;
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
        $st = $this->db->prepare(
            'UPDATE search_history SET deleted = 1, updated_at = ? WHERE user_id = ? AND deleted = 0'
        );
        $st->execute([now_ms(), $uid]);
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
                    "UPDATE `$table` SET deleted = 1, updated_at = ? WHERE user_id = ? AND deleted = 0"
                );
                $st->execute([$now, $uid]);
            }
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
    private function upsert(int $uid, string $table, array $def, array $item): bool
    {
        // Anahtarlar zorunlu
        foreach ($def['keys'] as $k) {
            if (!array_key_exists($k, $item)) return false;
        }
        $updatedAt = (int) ($item['updated_at'] ?? now_ms());
        $deleted   = !empty($item['deleted']) ? 1 : 0;

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
            if ($c === 'is_spoiler' && $v === null) {
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

        if ($existing === false) {
            // Yeni kayıt → INSERT
            $colNames = array_keys($values);
            $place    = implode(', ', array_fill(0, count($colNames), '?'));
            $colList  = '`' . implode('`, `', $colNames) . '`';
            $this->db->prepare("INSERT INTO `$table` ($colList) VALUES ($place)")
                     ->execute(array_values($values));
            return true;
        }

        // Eşit/yeni → anahtar dışındaki tüm kolonları güncelle.
        $updateCols = array_merge($def['cols'], ['updated_at', 'deleted']);
        $setParts = [];
        $setVals  = [];
        foreach ($updateCols as $c) {
            $setParts[] = "`$c` = ?";
            $setVals[]  = $values[$c];
        }
        $this->db->prepare("UPDATE `$table` SET " . implode(', ', $setParts) . " WHERE $whereSql")
                 ->execute(array_merge($setVals, $whereVals));
        return true;
    }
}
