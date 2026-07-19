<?php
declare(strict_types=1);

/** Shared helpers for {@see Social} domain modules. */
trait SocialSupportTrait
{
    private function notify(int $toUserId, int $fromUserId, string $type, array $extra = []): void
    {
        if ($this->fcm === null) {
            return;
        }
        try {
            $st = $this->db->prepare('SELECT display_name, username FROM users WHERE id = ?');
            $st->execute([$fromUserId]);
            $u = $st->fetch();
            $name = 'Biri';
            if ($u) {
                $name = trim((string) ($u['display_name'] ?? '')) !== ''
                    ? $u['display_name']
                    : '@' . ($u['username'] ?? 'kullanıcı');
            }

            $data = ['from_id' => $fromUserId];
            if ($type === 'request') {
                $title = 'Yeni arkadaşlık isteği';
                $body  = "$name seni arkadaş olarak eklemek istiyor.";
                $kind  = 'friend_request';
            } elseif ($type === 'recommend') {
                $movieTitle = (string) ($extra['title'] ?? '');
                $title = 'Arkadaşından öneri';
                $body  = "$name sana \"$movieTitle\" yapımını önerdi.";
                $kind  = 'friend_recommend';
                $data['movie_id'] = (string) ($extra['movie_id'] ?? '');
                $data['is_tv']    = (string) ($extra['is_tv'] ?? '0');
            } elseif ($type === 'couch_invite') {
                $title = 'Birlikte Seç daveti 🍿';
                $body  = "$name seninle film seçmek istiyor. Desten hazır!";
                $kind  = 'couch_invite';
                $data['session_id'] = (string) ($extra['session_id'] ?? '');
            } elseif ($type === 'couch_match') {
                $movieTitle = (string) ($extra['title'] ?? '');
                $title = 'Eşleşme! 🎬';
                $body  = "$name ile anlaştınız: \"$movieTitle\". İyi seyirler!";
                $kind  = 'couch_match';
                $data['session_id'] = (string) ($extra['session_id'] ?? '');
            } else {
                $title = 'Arkadaşlık isteği kabul edildi';
                $body  = "$name isteğini kabul etti.";
                $kind  = 'friend_accept';
            }
            $data['type'] = $kind;

            $this->fcm->sendToUser($this->db, $toUserId, $title, $body, $data);
        } catch (Throwable $e) {
            cinema_error('[Non-blocking] Social push notification failed: ' . $e->getMessage(), $toUserId);
        }
    }

    private function assertFriendship(int $uid, int $friendId, string $msg): void
    {
        $check = $this->db->prepare(
            'SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ? AND status = \'accepted\''
        );
        $check->execute([$uid, $friendId]);
        if (!$check->fetch()) {
            fail(403, $msg);
        }
    }

    private function fetchRatingsMap(int $uid): array
    {
        $st = $this->db->prepare(
            'SELECT r.movie_id, r.is_tv, r.rating,
                    COALESCE(t.genre_ids, tf.genre_ids) AS genre_ids, r.created_at
             FROM ratings r
             LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = \'tr\'
             LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = \'und\'
             WHERE r.user_id = ? AND r.deleted = 0 AND r.rating BETWEEN 0 AND 3'
        );
        $st->execute([$uid]);
        $map = [];
        foreach ($st->fetchAll() as $r) {
            $key = ($r['is_tv'] ? 'tv_' : 'movie_') . $r['movie_id'];
            $genres = json_decode((string) ($r['genre_ids'] ?? ''), true);
            $map[$key] = [
                'rating' => (int) $r['rating'],
                'genres' => is_array($genres) ? $genres : [],
                'created_at' => isset($r['created_at']) ? (int) $r['created_at'] : null,
            ];
        }
        return $map;
    }

    private function genreVector(array $ratingsMap): array
    {
        static $weights = [3 => 2.0, 2 => 1.0, 1 => -1.0, 0 => -2.0];
        $v = [];
        $now = time() * 1000;
        foreach ($ratingsMap as $r) {
            $w = $weights[$r['rating']] ?? 0.0;
            if ($w === 0.0) {
                continue;
            }
            
            // Apply client-identical time decay: exp(-0.00385 * daysElapsed)
            $createdAt = $r['created_at'] ?? $now;
            if ($createdAt < 10000000000) {
                // Convert seconds to milliseconds if needed (e.g. from unit tests)
                $createdAt *= 1000;
            }
            $daysElapsed = max(0.0, ($now - $createdAt) / (24 * 3600 * 1000));
            $decayFactor = exp(-0.00385 * $daysElapsed);
            $w *= $decayFactor;

            foreach ($r['genres'] as $g) {
                if (is_int($g)) {
                    $v[$g] = ($v[$g] ?? 0.0) + $w;
                }
            }
        }
        return $v;
    }

    private function cosine(array $a, array $b): float
    {
        if (!$a || !$b) {
            return 0.0;
        }
        $dot = 0.0;
        foreach ($a as $k => $va) {
            if (isset($b[$k])) {
                $dot += $va * $b[$k];
            }
        }
        $na = sqrt(array_sum(array_map(fn($x) => $x * $x, $a)));
        $nb = sqrt(array_sum(array_map(fn($x) => $x * $x, $b)));
        if ($na == 0.0 || $nb == 0.0) {
            return 0.0;
        }
        return $dot / ($na * $nb);
    }

    private function webRenderer(): SocialWebRenderer
    {
        return $this->webRenderer ??= new SocialWebRenderer($this->db);
    }
}
