<?php
declare(strict_types=1);

trait SocialMatchTrait
{
    // ─── GET /social/match/watchlist-intersection/{friend_id} ───────────────
    public function getWatchlistIntersection(int $uid, int $friendId): void
    {
        $locale = cinema_content_locale();
        // Arkadaşlık ilişkisini doğrula
        $check = $this->db->prepare('SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ? AND status = \'accepted\'');
        $check->execute([$uid, $friendId]);
        if (!$check->fetch()) {
            fail(403, 'Bu kullanıcının ortak listesine erişim yetkiniz yok.');
        }

        // Watchlist kesişimini al
        $st = $this->db->prepare(
            'SELECT w1.id, w1.is_tv,
                    COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.overview, tf.overview) AS overview,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date,
                    COALESCE(t.genre_ids, tf.genre_ids) AS genre_ids
             FROM watchlist w1
             JOIN watchlist w2 ON w1.id = w2.id AND w1.is_tv = w2.is_tv
             LEFT JOIN titles t ON t.tmdb_id = w1.id AND t.is_tv = w1.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = w1.id AND tf.is_tv = w1.is_tv AND tf.locale = \'und\'
             WHERE w1.user_id = ? AND w2.user_id = ?
               AND w1.deleted = 0 AND w2.deleted = 0
             ORDER BY w1.created_at DESC'
        );
        $st->execute([$locale, $uid, $friendId]);
        $items = $st->fetchAll();

        // JSON formatına uygun parse et
        foreach ($items as &$item) {
            if (isset($item['genre_ids'])) {
                $item['genre_ids'] = json_decode($item['genre_ids'], true);
            }
        }

        json_out(200, ['watchlist' => $items]);
    }

    // ─── GET /social/match/taste/{friend_id} ────────────────────────────────
    // İki arkadaşın zevk uyumunu 0-100 arası puanlar. İki sinyal harmanlanır:
    //  1) Ortak puanlanan yapımlarda anlaşma (puan farkı ne kadar az, o kadar iyi)
    //  2) Tür ağırlık vektörlerinin kosinüs benzerliği (istemcideki
    //     PrefsService ağırlıklarıyla aynı: 3→+2, 2→+1, 1→-1, 0→-2)
    public function getTasteMatch(int $uid, int $friendId): void
    {
        $this->assertFriendship($uid, $friendId, 'Bu kullanıcıyla uyum skorunu görme yetkiniz yok.');
        json_out(200, $this->computeTasteMatch($uid, $friendId));
    }

    // ─── GET /social/match/taste-all ────────────────────────────────────────
    // Tüm onaylı arkadaşların uyum skorlarını TEK istekte döner. İstemci
    // eskiden arkadaş başına ayrı istek atıyordu (N+1 HTTP); kendi puan
    // haritamız da burada bir kez çekilip tüm karşılaştırmalarda kullanılır.
    public function getAllTasteMatches(int $uid): void
    {
        $st = $this->db->prepare(
            'SELECT friend_id FROM friends WHERE user_id = ? AND status = \'accepted\''
        );
        $st->execute([$uid]);

        $mine = $this->fetchRatingsMap($uid);
        $scores = [];
        foreach ($st->fetchAll() as $row) {
            $friendId = (int) $row['friend_id'];
            $scores[] = ['friend_id' => $friendId]
                + $this->computeTasteMatch($uid, $friendId, $mine);
        }
        json_out(200, ['scores' => $scores]);
    }

    /**
     * İki kullanıcının uyum skorunu hesaplar; json_out YAPMAZ (tekil uç ve
     * toplu uç ortak kullanır). $mine önceden çekilmişse yeniden sorgulanmaz.
     */
    private function computeTasteMatch(int $uid, int $friendId, ?array $mine = null): array
    {
        $mine ??= $this->fetchRatingsMap($uid);
        $theirs = $this->fetchRatingsMap($friendId);

        // 1) Ortak yapımlarda anlaşma: 1 - |fark|/3 ortalaması (0..1)
        $common = 0;
        $agreeSum = 0.0;
        $bothLoved = 0;
        foreach ($mine as $key => $r1) {
            if (!isset($theirs[$key])) continue;
            $r2 = $theirs[$key];
            $common++;
            $agreeSum += 1.0 - abs($r1['rating'] - $r2['rating']) / 3.0;
            if ($r1['rating'] === 3 && $r2['rating'] === 3) $bothLoved++;
        }
        $agreement = $common > 0 ? $agreeSum / $common : 0.0;

        // 2) Tür vektörü kosinüsü (negatif = zıt zevkler → 0'a sabitlenir)
        $genreSim = max(0.0, $this->cosine(
            $this->genreVector($mine),
            $this->genreVector($theirs)
        ));

        // Harman: yeterli ortak yapım varsa anlaşma ağır basar; yoksa tür benzerliği.
        if ($common >= 3) {
            $score = (int) round(100 * (0.6 * $agreement + 0.4 * $genreSim));
        } else {
            $score = (int) round(100 * $genreSim);
        }

        return [
            'score'            => max(0, min(100, $score)),
            'common_count'     => $common,
            'both_loved'       => $bothLoved,
            'agreement'        => round($agreement, 4),
            'genre_similarity' => round($genreSim, 4),
            // Skor güvenilir mi? İki tarafta da veri yoksa UI rozeti gizleyebilir.
            'has_data'         => $common > 0 || (!empty($mine) && !empty($theirs)),
        ];
    }
}
