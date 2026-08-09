<?php
declare(strict_types=1);

final class SocialWebProfileCatalog
{
    public function __construct(private PDO $db) {}

    /** @return list<array<string, mixed>> */
    public function loadTopList(int $userId, bool $isTv, string $lang): array
    {
        $st = $this->db->prepare(
            'SELECT f.id AS movie_id, f.is_tv,
                    COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM favorites f
             LEFT JOIN titles t ON t.tmdb_id = f.id AND t.is_tv = f.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = f.id AND tf.is_tv = f.is_tv AND tf.locale = \'und\'
             WHERE f.user_id = ? AND f.is_tv = ? AND f.deleted = 0
             ORDER BY f.created_at ASC, f.id ASC
             LIMIT 20'
        );
        $st->execute([$lang, $userId, $isTv ? 1 : 0]);
        /** @var list<array<string, mixed>> $rows */
        $rows = $st->fetchAll();
        foreach ($rows as $index => &$row) {
            $row['rank'] = $index + 1;
        }
        unset($row);
        return $rows;
    }
}
