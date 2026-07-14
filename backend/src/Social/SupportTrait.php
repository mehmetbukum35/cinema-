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
            'SELECT movie_id, is_tv, rating, genre_ids FROM ratings
             WHERE user_id = ? AND deleted = 0 AND rating BETWEEN 0 AND 3'
        );
        $st->execute([$uid]);
        $map = [];
        foreach ($st->fetchAll() as $r) {
            $key = ($r['is_tv'] ? 'tv_' : 'movie_') . $r['movie_id'];
            $genres = json_decode((string) ($r['genre_ids'] ?? ''), true);
            $map[$key] = [
                'rating' => (int) $r['rating'],
                'genres' => is_array($genres) ? $genres : [],
            ];
        }
        return $map;
    }

    private function genreVector(array $ratingsMap): array
    {
        static $weights = [3 => 2.0, 2 => 1.0, 1 => -1.0, 0 => -2.0];
        $v = [];
        foreach ($ratingsMap as $r) {
            $w = $weights[$r['rating']] ?? 0.0;
            if ($w === 0.0) {
                continue;
            }
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
