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
                'UPDATE recommendations SET note = ?, poster_path = ?, seen = 0, created_at = ? WHERE id = ?'
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
    public function getRecommendations(int $uid): void
    {
        $st = $this->db->prepare(
            'SELECT r.id, r.movie_id, r.is_tv, r.title, r.poster_path, r.note, r.seen, r.created_at,
                    u.id as from_id, u.display_name as from_name, u.username as from_username
             FROM recommendations r
             JOIN users u ON u.id = r.from_user_id
             WHERE r.to_user_id = ?
             ORDER BY r.created_at DESC
             LIMIT 50'
        );
        $st->execute([$uid]);
        $items = $st->fetchAll();

        $unseen = 0;
        foreach ($items as &$item) {
            $item['seen'] = (bool) $item['seen'];
            if (!$item['seen']) $unseen++;
        }

        json_out(200, ['recommendations' => $items, 'unseen' => $unseen]);
    }

    // ─── POST /social/recommendations/seen ──────────────────────────────────
    public function markRecommendationsSeen(int $uid): void
    {
        $st = $this->db->prepare('UPDATE recommendations SET seen = 1 WHERE to_user_id = ? AND seen = 0');
        $st->execute([$uid]);
        json_out(200, ['ok' => true, 'marked' => $st->rowCount()]);
    }

    // ─── GET /social/recommendations/sent ───────────────────────────────────
    // Kullanıcının arkadaşlarına gönderdiği önerileri (alıcı bilgisiyle) döner.
    public function getSentRecommendations(int $uid): void
    {
        $st = $this->db->prepare(
            'SELECT r.id, r.movie_id, r.is_tv, r.title, r.poster_path, r.note, r.created_at,
                    u.id as to_id, u.display_name as to_name, u.username as to_username
             FROM recommendations r
             JOIN users u ON u.id = r.to_user_id
             WHERE r.from_user_id = ?
             ORDER BY r.created_at DESC
             LIMIT 50'
        );
        $st->execute([$uid]);
        json_out(200, ['sent' => $st->fetchAll()]);
    }
}
