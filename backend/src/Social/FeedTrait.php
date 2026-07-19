<?php
declare(strict_types=1);

trait SocialFeedTrait
{
    // ─── GET /social/friends/activity ───────────────────────────────────────
    public function getActivityFeed(int $uid, ?int $friendId = null): void
    {
        // Gizlenen (is_hidden=1) yorum metni akışa sızmaz; puan aktivitesi kalır.
        $sql = 'SELECT r.movie_id, r.is_tv, r.rating, t.title, t.poster_path, r.updated_at,
                       CASE WHEN r.is_hidden = 1 THEN NULL ELSE r.comment END as comment,
                       r.is_spoiler,
                       u.id as friend_id, u.display_name as friend_name, u.username as friend_username
                FROM friends f
                JOIN users u ON f.friend_id = u.id
                JOIN ratings r ON f.friend_id = r.user_id
                LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv
                WHERE f.user_id = ? AND f.status = \'accepted\' AND r.is_private = 0
                  AND f.friend_id NOT IN (SELECT blocked_user_id FROM user_blocks WHERE user_id = ?)
                  AND f.friend_id NOT IN (SELECT user_id FROM user_blocks WHERE blocked_user_id = ?)';
        
        $params = [$uid, $uid, $uid];
        if ($friendId !== null) {
            $sql .= ' AND f.friend_id = ?';
            $params[] = $friendId;
        }

        $sql .= ' AND (r.rating >= 2 OR (r.comment IS NOT NULL AND r.comment <> \'\'))
                  AND r.deleted = 0
                ORDER BY r.updated_at DESC
                LIMIT 50';

        $st = $this->db->prepare($sql);
        $st->execute($params);
        $feed = $st->fetchAll();

        json_out(200, ['activity' => $feed]);
    }
}
