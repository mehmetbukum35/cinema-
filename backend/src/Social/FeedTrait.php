<?php
declare(strict_types=1);

trait SocialFeedTrait
{
    // ─── GET /social/friends/activity ───────────────────────────────────────
    public function getActivityFeed(
        int $uid,
        ?int $friendId = null,
        ?string $cursor = null,
        int $limit = 50
    ): void
    {
        $limit = max(1, min(50, $limit));
        $locale = cinema_content_locale();
        // Gizlenen (is_hidden=1) yorum metni akışa sızmaz; puan aktivitesi kalır.
        $sql = 'SELECT r.movie_id, r.is_tv, r.rating,
                       COALESCE(t.title, tf.title) AS title,
                       COALESCE(t.poster_path, tf.poster_path) AS poster_path, r.updated_at,
                       CASE WHEN r.is_hidden = 1 THEN NULL ELSE r.comment END as comment,
                       r.is_spoiler,
                       u.id as friend_id, u.display_name as friend_name, u.username as friend_username
                FROM friends f
                JOIN users u ON f.friend_id = u.id
                JOIN ratings r ON f.friend_id = r.user_id
                LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = ?
                LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = \'und\'
                WHERE f.user_id = ? AND f.status = \'accepted\' AND r.is_private = 0
                  AND f.friend_id NOT IN (SELECT blocked_user_id FROM user_blocks WHERE user_id = ?)
                  AND f.friend_id NOT IN (SELECT user_id FROM user_blocks WHERE blocked_user_id = ?)';
        
        $params = [$locale, $uid, $uid, $uid];
        if ($friendId !== null) {
            $sql .= ' AND f.friend_id = ?';
            $params[] = $friendId;
        }

        $cursorData = $this->decodeActivityCursor($cursor);
        if ($cursorData !== null) {
            $sql .= ' AND (
                r.updated_at < ? OR
                (r.updated_at = ? AND f.friend_id < ?) OR
                (r.updated_at = ? AND f.friend_id = ? AND r.movie_id < ?) OR
                (r.updated_at = ? AND f.friend_id = ? AND r.movie_id = ? AND r.is_tv < ?)
            )';
            $params = array_merge($params, [
                $cursorData['updated_at'],
                $cursorData['updated_at'], $cursorData['friend_id'],
                $cursorData['updated_at'], $cursorData['friend_id'], $cursorData['movie_id'],
                $cursorData['updated_at'], $cursorData['friend_id'], $cursorData['movie_id'], $cursorData['is_tv'],
            ]);
        }

        // Gizli + düşük puanlı yorum satırı boş aktivite üretmesin; rating>=2
        // gizlense bile puan aktivitesi (yorum metni NULL) kalır.
        $sql .= ' AND (r.rating >= 2 OR (r.is_hidden = 0 AND r.comment IS NOT NULL AND r.comment <> \'\'))
                  AND r.deleted = 0
                ORDER BY r.updated_at DESC, f.friend_id DESC, r.movie_id DESC, r.is_tv DESC
                LIMIT ' . ($limit + 1);

        $st = $this->db->prepare($sql);
        $st->execute($params);
        $feed = $st->fetchAll();
        $hasMore = count($feed) > $limit;
        if ($hasMore) array_pop($feed);
        $nextCursor = null;
        if ($hasMore && $feed !== []) {
            $last = $feed[array_key_last($feed)];
            $nextCursor = rtrim(strtr(base64_encode((string) json_encode([
                'updated_at' => (int) $last['updated_at'],
                'friend_id' => (int) $last['friend_id'],
                'movie_id' => (int) $last['movie_id'],
                'is_tv' => (int) $last['is_tv'],
            ])), '+/', '-_'), '=');
        }

        json_out(200, [
            'activity' => $feed,
            'next_cursor' => $nextCursor,
            'has_more' => $hasMore,
        ]);
    }

    private function decodeActivityCursor(?string $cursor): ?array
    {
        if ($cursor === null || $cursor === '') return null;
        $normalized = strtr($cursor, '-_', '+/');
        $normalized .= str_repeat('=', (4 - strlen($normalized) % 4) % 4);
        $raw = base64_decode($normalized, true);
        if ($raw === false) fail(422, 'Geçersiz aktivite cursor değeri.');
        $data = json_decode($raw, true);
        if (!is_array($data)) fail(422, 'Geçersiz aktivite cursor değeri.');
        foreach (['updated_at', 'friend_id', 'movie_id', 'is_tv'] as $key) {
            if (!isset($data[$key]) || !is_numeric($data[$key])) {
                fail(422, 'Geçersiz aktivite cursor değeri.');
            }
        }
        return array_map('intval', $data);
    }
}
