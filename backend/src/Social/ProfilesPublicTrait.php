<?php
declare(strict_types=1);

trait SocialProfilesPublicTrait
{
    // ─── POST /social/profile/like ────────────────────────────────────────────
    // Bir üyenin herkese açık profilini (listelerini) beğen / beğeniyi geri al.
    // Girdi: { owner_id: int, liked: bool }. Kullanıcı başına tek beğeni
    // (PK voter_id+owner_id); tekrar beğenmek idempotenttir.
    public function likeProfile(int $uid, array $in): void
    {
        $ownerId = (int) ($in['owner_id'] ?? 0);
        $liked = (bool) ($in['liked'] ?? true);
        if ($ownerId <= 0) fail(422, 'owner_id gerekli.');
        if ($ownerId === $uid) fail(422, 'Kendi profilini beğenemezsin.');

        $st = $this->db->prepare('SELECT is_public FROM users WHERE id = ?');
        $st->execute([$ownerId]);
        $row = $st->fetch();
        if (!$row) fail(404, 'Kullanıcı bulunamadı.');
        if ((int) $row['is_public'] !== 1) fail(403, 'Bu profil herkese açık değil.');

        if ($liked) {
            $check = $this->db->prepare(
                'SELECT 1 FROM profile_likes WHERE voter_id = ? AND owner_id = ?'
            );
            $check->execute([$uid, $ownerId]);
            if (!$check->fetch()) {
                try {
                    $ins = $this->db->prepare(
                        'INSERT INTO profile_likes (voter_id, owner_id, created_at)
                         VALUES (?, ?, ?)'
                    );
                    $ins->execute([$uid, $ownerId, now_ms()]);
                } catch (PDOException $e) {
                    // Eşzamanlı çift istekte PK ihlali olabilir — beğeni zaten
                    // var demektir, idempotent kabul edilir.
                }
            }
        } else {
            $del = $this->db->prepare(
                'DELETE FROM profile_likes WHERE voter_id = ? AND owner_id = ?'
            );
            $del->execute([$uid, $ownerId]);
        }

        $cnt = $this->db->prepare('SELECT COUNT(*) FROM profile_likes WHERE owner_id = ?');
        $cnt->execute([$ownerId]);
        json_out(200, ['ok' => true, 'liked' => $liked, 'like_count' => (int) $cnt->fetchColumn()]);
    }

    // ─── GET /social/profiles/top ─────────────────────────────────────────────
    // En çok beğeni alan 20 herkese açık üye. Soğuk başlangıçta ekran boş
    // kalmasın diye beğenisi olmayan üyeler de listelenir; eşitlik, beğendiği
    // yapım sayısıyla (rating >= 2) bozulur. Her üye için en sevdiği
    // yapımlardan 4 afiş önizlemesi eklenir.
    public function getTopProfiles(int $uid): void
    {
        $locale = cinema_content_locale();
        $st = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username,
                    (SELECT COUNT(*) FROM profile_likes pl
                      WHERE pl.owner_id = u.id) AS like_count,
                    EXISTS(SELECT 1 FROM profile_likes pl2
                            WHERE pl2.owner_id = u.id AND pl2.voter_id = ?) AS me_liked,
                    (SELECT COUNT(*) FROM ratings r
                      WHERE r.user_id = u.id AND r.rating >= 2 AND r.deleted = 0) AS liked_titles
             FROM users u
             WHERE u.is_public = 1 AND u.username IS NOT NULL
             ORDER BY like_count DESC, liked_titles DESC, u.id ASC
             LIMIT 20'
        );
        $st->execute([$uid]);

        $posterStmt = $this->db->prepare(
             'SELECT COALESCE(t.title, tf.title) AS title,
                     COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                     r.movie_id, r.is_tv FROM ratings r
              LEFT JOIN titles t ON t.tmdb_id = r.movie_id AND t.is_tv = r.is_tv AND t.locale = ?
              LEFT JOIN titles tf ON tf.tmdb_id = r.movie_id AND tf.is_tv = r.is_tv AND tf.locale = \'und\'
              WHERE r.user_id = ? AND r.rating >= 2 AND r.deleted = 0
                AND r.is_private = 0 AND COALESCE(t.poster_path, tf.poster_path) IS NOT NULL
              ORDER BY r.rating DESC, r.updated_at DESC
              LIMIT 10'
        );

        $profiles = [];
        foreach ($st->fetchAll() as $u) {
            $posterStmt->execute([$locale, (int) $u['id']]);
            $previews = [];
            foreach ($posterStmt->fetchAll() as $p) {
                $previews[] = [
                    'title'       => $p['title'],
                    'poster_path' => $p['poster_path'],
                    'movie_id'    => (int) $p['movie_id'],
                    'is_tv'       => (int) $p['is_tv'] === 1,
                ];
            }
            $profiles[] = [
                'id'           => (int) $u['id'],
                'display_name' => $u['display_name'],
                'username'     => $u['username'],
                'like_count'   => (int) $u['like_count'],
                'me_liked'     => (int) $u['me_liked'] === 1,
                'is_me'        => (int) $u['id'] === $uid,
                'liked_titles' => (int) $u['liked_titles'],
                'previews'     => $previews,
            ];
        }
        json_out(200, ['profiles' => $profiles]);
    }

    // ─── GET /profile/{username} (Halka Açık Web Görünümü) ───────────────────
    public function renderPublicWebProfile(string $username): void
    {
        $this->webRenderer()->renderPublicWebProfile($username);
    }

    public function getFriendSignals(int $uid): void
    {
        $st = $this->db->prepare(
            'SELECT r.movie_id, r.is_tv, u.display_name as friend_name
             FROM friends f
             JOIN users u ON f.friend_id = u.id
             JOIN ratings r ON f.friend_id = r.user_id
             WHERE f.user_id = ? AND f.status = \'accepted\' AND r.rating >= 2 AND r.deleted = 0 AND r.is_private = 0
             ORDER BY r.updated_at DESC
             LIMIT 1000'
        );
        $st->execute([$uid]);
        $rows = $st->fetchAll();

        // Group by movie key: e.g. "movie_123" or "tv_456"
        $signals = [];
        foreach ($rows as $row) {
            $key = ($row['is_tv'] ? 'tv_' : 'movie_') . $row['movie_id'];
            if (!isset($signals[$key])) {
                $signals[$key] = [];
            }
            $signals[$key][] = $row['friend_name'];
        }

        // (object): boş sinyal kümesi JSON'a `[]` yerine `{}` yazılsın —
        // istemci Map bekler (couch my_votes ile aynı PHP/JSON tuzağı).
        json_out(200, ['signals' => (object) $signals]);
    }

    // ─── GET /download (Halka Açık İndirme Sayfası) ──────────────────────────
    public function renderDownloadPage(): void
    {
        $this->webRenderer()->renderDownloadPage();
    }
}
