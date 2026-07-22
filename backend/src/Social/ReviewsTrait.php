<?php
declare(strict_types=1);

trait SocialReviewsTrait
{
    private const AUTO_HIDE_THRESHOLD = 3;
    private const REPORT_REASONS = ['profanity', 'spam', 'spoiler', 'harassment', 'other'];

    public function getTitleReviews(int $uid, string $type, int $id): void
    {
        $isTV = ($type === 'tv') ? 1 : 0;

        // Engelleme iki yönlü işler: benim engellediklerimin yorumunu görmem,
        // beni engelleyenin yorumunu da görmem (taciz döngüsünü kapatır).
        $notBlocked =
            'AND r.user_id NOT IN (SELECT blocked_user_id FROM user_blocks WHERE user_id = ?)
             AND r.user_id NOT IN (SELECT user_id FROM user_blocks WHERE blocked_user_id = ?)';

        // 1. Friends' reviews — user_id, şikayet/engelleme UI'ının hedefi için döner.
        $stFriends = $this->db->prepare(
            'SELECT r.user_id, r.rating, r.comment, r.is_spoiler, r.updated_at,
                    u.display_name as friend_name, u.username as friend_username
             FROM friends f
             JOIN users u ON f.friend_id = u.id
             JOIN ratings r ON f.friend_id = r.user_id
              WHERE f.user_id = ? AND f.status = \'accepted\'
                AND r.movie_id = ? AND r.is_tv = ?
                AND r.comment IS NOT NULL AND r.comment <> \'\'
                AND r.deleted = 0 AND r.is_private = 0 AND r.is_hidden = 0
                ' . $notBlocked . '
              ORDER BY r.updated_at DESC
              LIMIT 50'
        );
        $stFriends->execute([$uid, $id, $isTV, $uid, $uid]);
        $friends = $stFriends->fetchAll();

        // 2. Community reviews (excluding user and their accepted friends)
        $stCommunity = $this->db->prepare(
            'SELECT r.user_id, r.rating, r.comment, r.is_spoiler, r.updated_at,
                    u.display_name as friend_name, u.username as friend_username
             FROM ratings r
             JOIN users u ON r.user_id = u.id
              WHERE r.movie_id = ? AND r.is_tv = ?
                AND r.comment IS NOT NULL AND r.comment <> \'\'
                AND r.deleted = 0
                AND r.is_private = 0
                AND r.is_hidden = 0
                AND u.is_public = 1
                AND r.user_id <> ?
                AND r.user_id NOT IN (
                    SELECT friend_id FROM friends WHERE user_id = ? AND status = \'accepted\'
                )
                ' . $notBlocked . '
              ORDER BY r.updated_at DESC
              LIMIT 20'
        );
        $stCommunity->execute([$id, $isTV, $uid, $uid, $uid, $uid]);
        $community = $stCommunity->fetchAll();

        json_out(200, [
            'reviews' => $friends, // Geriye dönük uyumluluk
            'friends' => $friends,
            'community' => $community
        ]);
    }

    // ─── POST /social/reviews/report ─────────────────────────────────────────
    // Yorumlar ratings satırlarıdır; ayrı bir id yoktur — şikayet hedefi
    // (user_id, movie_id, is_tv) üçlüsüdür. Aynı kullanıcı aynı yorumu bir kez
    // şikayet edebilir (PK). AUTO_HIDE_THRESHOLD farklı kullanıcıdan açık
    // şikayet birikince yorum otomatik gizlenir; moderatör panelinden geri
    // açılabilir. Böylece moderatör uyurken topluluk kendini korur.
    public function reportReview(int $uid, array $in): void
    {
        $reportedId = (int) ($in['user_id'] ?? 0);
        $movieId    = (int) ($in['movie_id'] ?? 0);
        $isTV       = ((int) ($in['is_tv'] ?? 0)) === 1 ? 1 : 0;
        $reason     = (string) ($in['reason'] ?? 'other');
        if (!in_array($reason, self::REPORT_REASONS, true)) $reason = 'other';

        if ($reportedId <= 0 || $movieId <= 0) fail(422, 'user_id ve movie_id gerekli.');
        if ($reportedId === $uid) fail(422, 'Kendi yorumunu şikayet edemezsin.');

        $st = $this->db->prepare(
            'SELECT 1 FROM ratings
              WHERE user_id = ? AND movie_id = ? AND is_tv = ?
                AND deleted = 0 AND is_private = 0 AND is_hidden = 0
                AND comment IS NOT NULL AND comment <> \'\''
        );
        $st->execute([$reportedId, $movieId, $isTV]);
        if (!$st->fetch()) fail(404, 'Şikayet edilecek yorum bulunamadı.');

        // Motor bağımsız idempotent ekleme (önce kontrol, sonra yaz).
        $chk = $this->db->prepare(
            'SELECT 1 FROM review_reports
              WHERE reporter_id = ? AND reported_user_id = ? AND movie_id = ? AND is_tv = ?'
        );
        $chk->execute([$uid, $reportedId, $movieId, $isTV]);
        if (!$chk->fetch()) {
            $ins = $this->db->prepare(
                'INSERT INTO review_reports
                   (reporter_id, reported_user_id, movie_id, is_tv, reason, status, created_at)
                 VALUES (?, ?, ?, ?, ?, \'open\', ?)'
            );
            $ins->execute([$uid, $reportedId, $movieId, $isTV, $reason, now_ms()]);
        }

        $cnt = $this->db->prepare(
            'SELECT COUNT(DISTINCT reporter_id) FROM review_reports
              WHERE reported_user_id = ? AND movie_id = ? AND is_tv = ? AND status = \'open\''
        );
        $cnt->execute([$reportedId, $movieId, $isTV]);
        $hidden = false;
        if ((int) $cnt->fetchColumn() >= self::AUTO_HIDE_THRESHOLD) {
            // Only auto-hide public comments; private ratings stay private.
            $up = $this->db->prepare(
                'UPDATE ratings SET is_hidden = 1
                  WHERE user_id = ? AND movie_id = ? AND is_tv = ? AND is_private = 0'
            );
            $up->execute([$reportedId, $movieId, $isTV]);
            $hidden = true;
        }
        json_out(200, ['ok' => true, 'auto_hidden' => $hidden]);
    }

    // ─── POST /social/users/block ────────────────────────────────────────────
    // Engelleme mevcut arkadaşlığı da (iki yönde) koparır: engellediğin biriyle
    // arkadaş kalmak tutarsız olurdu ve arkadaş sorguları blok filtresinden geçmez.
    public function blockUser(int $uid, array $in): void
    {
        $blockedId = (int) ($in['user_id'] ?? 0);
        if ($blockedId <= 0) fail(422, 'user_id gerekli.');
        if ($blockedId === $uid) fail(422, 'Kendini engelleyemezsin.');

        $st = $this->db->prepare('SELECT 1 FROM users WHERE id = ?');
        $st->execute([$blockedId]);
        if (!$st->fetch()) fail(404, 'Kullanıcı bulunamadı.');

        $chk = $this->db->prepare(
            'SELECT 1 FROM user_blocks WHERE user_id = ? AND blocked_user_id = ?'
        );
        $chk->execute([$uid, $blockedId]);
        if (!$chk->fetch()) {
            $ins = $this->db->prepare(
                'INSERT INTO user_blocks (user_id, blocked_user_id, created_at) VALUES (?, ?, ?)'
            );
            $ins->execute([$uid, $blockedId, now_ms()]);
        }

        $del = $this->db->prepare(
            'DELETE FROM friends
              WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)'
        );
        $del->execute([$uid, $blockedId, $blockedId, $uid]);

        // Engellenen kişinin önceki önerileri inbox'ta kalmasın.
        $purge = $this->db->prepare(
            'DELETE FROM recommendations
              WHERE (to_user_id = ? AND from_user_id = ?)
                 OR (to_user_id = ? AND from_user_id = ?)'
        );
        $purge->execute([$uid, $blockedId, $blockedId, $uid]);

        // Engellenen hesaplar birbirlerinin profil beğenilerine de katkıda
        // bulunmamalı; iki yöndeki eski oyları temizle.
        $purgeLikes = $this->db->prepare(
            'DELETE FROM profile_likes
              WHERE (voter_id = ? AND owner_id = ?)
                 OR (voter_id = ? AND owner_id = ?)'
        );
        $purgeLikes->execute([$uid, $blockedId, $blockedId, $uid]);
        $this->invalidateTopProfilesCache();

        json_out(200, ['ok' => true]);
    }

    // ─── POST /social/users/unblock ──────────────────────────────────────────
    public function unblockUser(int $uid, array $in): void
    {
        $blockedId = (int) ($in['user_id'] ?? 0);
        if ($blockedId <= 0) fail(422, 'user_id gerekli.');
        $del = $this->db->prepare(
            'DELETE FROM user_blocks WHERE user_id = ? AND blocked_user_id = ?'
        );
        $del->execute([$uid, $blockedId]);
        json_out(200, ['ok' => true, 'removed' => $del->rowCount() > 0]);
    }

    // ─── GET /social/users/blocked ───────────────────────────────────────────
    public function getBlockedUsers(int $uid): void
    {
        $st = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username, b.created_at
             FROM user_blocks b
             JOIN users u ON b.blocked_user_id = u.id
              WHERE b.user_id = ?
              ORDER BY b.created_at DESC'
        );
        $st->execute([$uid]);
        json_out(200, ['blocked' => $st->fetchAll()]);
    }

    // ─── GET /titles/{type}/{id}/score ──────────────────────────────────────
    // cinema+ üyelerinin topluluk skoru. Ortalama yerine "beğeni yüzdesi"
    // (Rotten Tomatoes mantığı): İyi(2)+Harika(3) oranı. 4'lü ölçekte ortalama
    // anlamsız olurdu; yüzde TMDB'nin 10'luk yıldızından da net ayrışır.
    // Soğuk başlangıç: eşik altındaki az oyda yüzde yanıltıcı olur; istemci
    // 'enough' bayrağına göre yüzdeyi mi yoksa yalın oy sayısını mı göstereceğine
    // karar verir (arkadaş sinyaline düşebilir).
    public function getTitleScore(int $uid, string $type, int $id): void
    {
        $isTV = ($type === 'tv') ? 1 : 0;
        // Puanlar 0..3 aralığında; -1 (izlenmedi) sayılmaz.
        $st = $this->db->prepare(
            'SELECT
                COUNT(*)                             AS total,
                SUM(CASE WHEN rating >= 2 THEN 1 ELSE 0 END) AS liked,
                SUM(CASE WHEN rating = 3 THEN 1 ELSE 0 END)  AS harika,
                SUM(CASE WHEN rating = 2 THEN 1 ELSE 0 END)  AS iyi,
                SUM(CASE WHEN rating = 1 THEN 1 ELSE 0 END)  AS eh,
                SUM(CASE WHEN rating = 0 THEN 1 ELSE 0 END)  AS berbat
             FROM ratings
             WHERE movie_id = ? AND is_tv = ? AND deleted = 0 AND is_private = 0 AND rating BETWEEN 0 AND 3'
        );
        $st->execute([$id, $isTV]);
        $row = $st->fetch() ?: [];

        $total  = (int) ($row['total'] ?? 0);
        $liked  = (int) ($row['liked'] ?? 0);
        // Yüzdenin güvenilir sayılması için minimum oy eşiği.
        $threshold = 5;
        $likedPct = $total > 0 ? (int) round(100 * $liked / $total) : 0;

        json_out(200, [
            'total'        => $total,
            'liked_percent'=> $likedPct,
            'enough'       => $total >= $threshold,
            'threshold'    => $threshold,
            'distribution' => [
                'harika' => (int) ($row['harika'] ?? 0),
                'iyi'    => (int) ($row['iyi'] ?? 0),
                'eh'     => (int) ($row['eh'] ?? 0),
                'berbat' => (int) ($row['berbat'] ?? 0),
            ],
        ]);
    }
}
