<?php
declare(strict_types=1);

trait SocialRecommendationsTrait
{
    // ─── POST /social/recommend ─────────────────────────────────────────────
    // Arkadaşa film/dizi önerir. Aynı yapım aynı arkadaşa tekrar önerilirse
    // mevcut kayıt tazelenir (spam/çift kayıt oluşmaz). Push bildirimi gönderilir.
    public function recommend(int $uid, array $in): void
    {
        $friendId = (int) ($in['friend_id'] ?? 0);
        $movieId  = (int) ($in['movie_id'] ?? 0);
        $isTv     = !empty($in['is_tv']) ? 1 : 0;
        $title    = trim((string) ($in['title'] ?? ''));
        $poster   = trim((string) ($in['poster_path'] ?? '')) ?: null;
        $note     = trim(mb_substr((string) ($in['note'] ?? ''), 0, 280)) ?: null;

        if ($friendId <= 0 || $movieId <= 0 || $title === '') {
            fail(422, 'friend_id, movie_id ve title gerekli.');
        }
        if ($poster !== null) $poster = mb_substr($poster, 0, 255);
        $title = mb_substr($title, 0, 512);

        $this->assertFriendship($uid, $friendId, 'Yalnızca arkadaşlarınıza öneri gönderebilirsiniz.');

        // Motor-bağımsız upsert (bkz. Sync::upsert deseni): önce kontrol, sonra yaz.
        $t = now_ms();
        $sel = $this->db->prepare(
            'SELECT id FROM recommendations
             WHERE from_user_id = ? AND to_user_id = ? AND movie_id = ? AND is_tv = ?'
        );
        $sel->execute([$uid, $friendId, $movieId, $isTv]);
        $existingId = $sel->fetchColumn();

        if ($existingId !== false) {
            $up = $this->db->prepare(
                'UPDATE recommendations
                 SET note = ?, poster_path = ?, seen = 0,
                     sender_deleted = 0, recipient_deleted = 0, created_at = ?
                 WHERE id = ?'
            );
            $up->execute([$note, $poster, $t, (int) $existingId]);
        } else {
            $ins = $this->db->prepare(
                'INSERT INTO recommendations
                 (from_user_id, to_user_id, movie_id, is_tv, title, poster_path, note, seen, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)'
            );
            $ins->execute([$uid, $friendId, $movieId, $isTv, $title, $poster, $note, $t]);
        }

        $this->notify($friendId, $uid, 'recommend', [
            'title'    => $title,
            'movie_id' => $movieId,
            'is_tv'    => $isTv,
        ]);
        json_out(200, ['ok' => true]);
    }

    // ─── GET /social/recommendations ────────────────────────────────────────
    // Kullanıcıya gelen önerileri (gönderen bilgisiyle) döner.
    public function getRecommendations(int $uid, ?string $cursor = null, int $limit = 30): void
    {
        $limit = max(1, min($limit, 50));
        $cursorData = $this->decodeRecommendationCursor($cursor);
        $cursorSql = '';
        $params = [$uid, $uid, $uid];
        if ($cursorData !== null) {
            $cursorSql = ' AND (r.created_at < ? OR (r.created_at = ? AND r.id < ?))';
            array_push($params, $cursorData['created_at'], $cursorData['created_at'], $cursorData['id']);
        }
        $st = $this->db->prepare(
            'SELECT r.id, r.movie_id, r.is_tv, r.title, r.poster_path, r.note, r.seen, r.created_at,
                    u.id as from_id, u.display_name as from_name, u.username as from_username
             FROM recommendations r
             JOIN users u ON u.id = r.from_user_id
             WHERE r.to_user_id = ?
               AND r.recipient_deleted = 0
               AND r.from_user_id NOT IN (SELECT blocked_user_id FROM user_blocks WHERE user_id = ?)
               AND r.from_user_id NOT IN (SELECT user_id FROM user_blocks WHERE blocked_user_id = ?)
             ' . $cursorSql . '
             ORDER BY r.created_at DESC, r.id DESC
             LIMIT ' . ($limit + 1)
        );
        $st->execute($params);
        $items = $st->fetchAll();
        $hasMore = count($items) > $limit;
        if ($hasMore) array_pop($items);
        foreach ($items as &$item) {
            $item['seen'] = (bool) $item['seen'];
        }
        unset($item);

        $count = $this->db->prepare(
            'SELECT COUNT(*) FROM recommendations r
             WHERE r.to_user_id = ? AND r.seen = 0 AND r.recipient_deleted = 0
               AND r.from_user_id NOT IN (SELECT blocked_user_id FROM user_blocks WHERE user_id = ?)
               AND r.from_user_id NOT IN (SELECT user_id FROM user_blocks WHERE blocked_user_id = ?)'
        );
        $count->execute([$uid, $uid, $uid]);
        $unseen = (int) $count->fetchColumn();
        $nextCursor = $hasMore && $items !== []
            ? $this->encodeRecommendationCursor($items[array_key_last($items)])
            : null;

        json_out(200, [
            'recommendations' => $items,
            'unseen' => $unseen,
            'next_cursor' => $nextCursor,
            'has_more' => $hasMore,
        ]);
    }

    // ─── POST /social/recommendations/seen ──────────────────────────────────
    public function markRecommendationsSeen(int $uid): void
    {
        $st = $this->db->prepare(
            'UPDATE recommendations
             SET seen = 1
             WHERE to_user_id = ? AND seen = 0 AND recipient_deleted = 0'
        );
        $st->execute([$uid]);
        json_out(200, ['ok' => true, 'marked' => $st->rowCount()]);
    }

    // ─── GET /social/recommendations/sent ───────────────────────────────────
    // Kullanıcının arkadaşlarına gönderdiği önerileri (alıcı bilgisiyle) döner.
    public function getSentRecommendations(int $uid, ?string $cursor = null, int $limit = 30): void
    {
        $limit = max(1, min($limit, 50));
        $cursorData = $this->decodeRecommendationCursor($cursor);
        $cursorSql = '';
        $params = [$uid];
        if ($cursorData !== null) {
            $cursorSql = ' AND (r.created_at < ? OR (r.created_at = ? AND r.id < ?))';
            array_push($params, $cursorData['created_at'], $cursorData['created_at'], $cursorData['id']);
        }
        $st = $this->db->prepare(
            'SELECT r.id, r.movie_id, r.is_tv, r.title, r.poster_path, r.note, r.created_at,
                    u.id as to_id, u.display_name as to_name, u.username as to_username
             FROM recommendations r
             JOIN users u ON u.id = r.to_user_id
             WHERE r.from_user_id = ?
               AND r.sender_deleted = 0
             ' . $cursorSql . '
             ORDER BY r.created_at DESC, r.id DESC
             LIMIT ' . ($limit + 1)
        );
        $st->execute($params);
        $items = $st->fetchAll();
        $hasMore = count($items) > $limit;
        if ($hasMore) array_pop($items);
        $nextCursor = $hasMore && $items !== []
            ? $this->encodeRecommendationCursor($items[array_key_last($items)])
            : null;
        json_out(200, ['sent' => $items, 'next_cursor' => $nextCursor, 'has_more' => $hasMore]);
    }

    private function encodeRecommendationCursor(array $item): string
    {
        return rtrim(strtr(base64_encode(json_encode([
            'created_at' => (int) $item['created_at'],
            'id' => (int) $item['id'],
        ], JSON_THROW_ON_ERROR)), '+/', '-_'), '=');
    }

    private function decodeRecommendationCursor(?string $cursor): ?array
    {
        if ($cursor === null || $cursor === '') return null;
        $normalized = strtr($cursor, '-_', '+/');
        $normalized .= str_repeat('=', (4 - strlen($normalized) % 4) % 4);
        $raw = base64_decode($normalized, true);
        if ($raw === false) fail(422, 'Geçersiz öneri cursor değeri.');
        $data = json_decode($raw, true);
        if (!is_array($data) || !isset($data['created_at'], $data['id'])) {
            fail(422, 'Geçersiz öneri cursor değeri.');
        }
        return ['created_at' => (int) $data['created_at'], 'id' => (int) $data['id']];
    }

    // ─── DELETE /social/recommendations/{id} ───────────────────────────────
    // Her taraf yalnızca kendi görünümünü temizler. İki taraf da gizlediyse
    // artık kimseye görünmeyen fiziksel kayıt güvenle kaldırılır.
    public function deleteRecommendation(int $uid, int $recommendationId): void
    {
        if ($recommendationId <= 0) fail(422, 'Geçerli bir öneri kimliği gerekli.');

        $st = $this->db->prepare(
            'SELECT from_user_id, to_user_id FROM recommendations WHERE id = ?'
        );
        $st->execute([$recommendationId]);
        $item = $st->fetch();
        if (!$item || ($uid !== (int) $item['from_user_id'] && $uid !== (int) $item['to_user_id'])) {
            fail(404, 'Öneri bulunamadı.');
        }

        $column = $uid === (int) $item['from_user_id'] ? 'sender_deleted' : 'recipient_deleted';
        $up = $this->db->prepare("UPDATE recommendations SET $column = 1 WHERE id = ?");
        $up->execute([$recommendationId]);

        $cleanup = $this->db->prepare(
            'DELETE FROM recommendations WHERE id = ? AND sender_deleted = 1 AND recipient_deleted = 1'
        );
        $cleanup->execute([$recommendationId]);
        json_out(200, ['ok' => true]);
    }
}
