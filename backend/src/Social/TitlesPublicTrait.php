<?php
declare(strict_types=1);

/**
 * Topluluk "Popüler Top 20" başlık listeleri (film + dizi).
 *
 * Ağır toplama (COUNT(DISTINCT user_id) GROUP BY id) istek yolunda DEĞİL; cron
 * (Maintenance::recomputePopularTitles) `popular_titles` tablosuna önhesaplar.
 * Bu uç yalnızca o 20 satırı okur ve `titles`'tan aktif locale + `und` yedeği
 * ile metadata'yı birleştirir. Kimlik doğrulaması gerektirmez — misafirler de
 * görebilir; kötüye kullanım IP başına rate-limit ile sınırlanır.
 */
trait SocialTitlesPublicTrait
{
    // GET /titles/popular?type=movie|tv
    public function getPopularTitles(string $type): void
    {
        $isTV = ($type === 'tv') ? 1 : 0;
        $locale = cinema_content_locale();

        $st = $this->db->prepare(
            'SELECT p.`rank`, p.tmdb_id, p.is_tv, p.votes,
                    COALESCE(t.title, tf.title)                 AS title,
                    COALESCE(t.poster_path, tf.poster_path)     AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.overview, tf.overview)           AS overview,
                    COALESCE(t.vote_average, tf.vote_average)   AS vote_average,
                    COALESCE(t.release_date, tf.release_date)   AS release_date,
                    COALESCE(t.popularity, tf.popularity)       AS popularity,
                    COALESCE(t.genre_ids, tf.genre_ids)         AS genre_ids
             FROM popular_titles p
             LEFT JOIN titles t
               ON t.tmdb_id = p.tmdb_id AND t.is_tv = p.is_tv AND t.locale = ?
             LEFT JOIN titles tf
               ON tf.tmdb_id = p.tmdb_id AND tf.is_tv = p.is_tv AND tf.locale = \'und\'
             WHERE p.is_tv = ?
             ORDER BY p.`rank` ASC'
        );
        $st->execute([$locale, $isTV]);

        $titles = [];
        $displayRank = 1;
        foreach ($st->fetchAll() as $row) {
            // Metadata henüz `titles`'a düşmemiş başlıkları atla — istemci poster
            // olmadan boş kart gösteremez.
            if (($row['poster_path'] ?? null) === null && ($row['title'] ?? null) === null) {
                continue;
            }
            $titles[] = [
                'rank'          => $displayRank++,
                'tmdb_id'       => (int) $row['tmdb_id'],
                'is_tv'         => (int) $row['is_tv'] === 1,
                'votes'         => (int) $row['votes'],
                'title'         => $row['title'],
                'poster_path'   => $row['poster_path'],
                'backdrop_path' => $row['backdrop_path'],
                'overview'      => $row['overview'],
                'vote_average'  => $row['vote_average'] !== null ? (float) $row['vote_average'] : null,
                'release_date'  => $row['release_date'],
                'popularity'    => $row['popularity'] !== null ? (float) $row['popularity'] : null,
                'genre_ids'     => $row['genre_ids'],
            ];
        }

        json_out(200, ['titles' => $titles]);
    }
}
