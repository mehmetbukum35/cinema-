<?php
declare(strict_types=1);
// Sosyal ağ, arkadaşlık, zevk uyumu ve ortak izleme listesi kesişimi iş mantığı.

class Social
{
    public function __construct(
        private PDO $db,
        private ?SocialWebRenderer $webRenderer = null,
        private ?Fcm $fcm = null
    ) {}

    // ─── POST /social/device/register ───────────────────────────────────────
    // İstemci FCM token'ını kaydeder/günceller. Token tekildir (PK): aynı cihaz
    // başka bir hesaba geçtiyse user_id güncellenir, çift kayıt oluşmaz.
    public function registerDevice(int $uid, array $in): void
    {
        $token = trim((string) ($in['token'] ?? ''));
        if ($token === '') fail(422, 'token gerekli.');
        $platform = substr(trim((string) ($in['platform'] ?? '')), 0, 20) ?: null;

        $t = now_ms();
        $check = $this->db->prepare('SELECT 1 FROM device_tokens WHERE token = ?');
        $check->execute([$token]);
        if ($check->fetch()) {
            $up = $this->db->prepare(
                'UPDATE device_tokens SET user_id = ?, platform = ?, updated_at = ? WHERE token = ?'
            );
            $up->execute([$uid, $platform, $t, $token]);
        } else {
            $ins = $this->db->prepare(
                'INSERT INTO device_tokens (user_id, token, platform, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?)'
            );
            $ins->execute([$uid, $token, $platform, $t, $t]);
        }
        json_out(200, ['ok' => true]);
    }

    // ─── POST /social/device/unregister (çıkış yaparken) ────────────────────
    public function unregisterDevice(int $uid, array $in): void
    {
        $token = trim((string) ($in['token'] ?? ''));
        if ($token === '') fail(422, 'token gerekli.');
        $del = $this->db->prepare('DELETE FROM device_tokens WHERE token = ? AND user_id = ?');
        $del->execute([$token, $uid]);
        json_out(200, ['ok' => true]);
    }

    // ─── Push bildirimi (best-effort: ana akışı asla bozmaz) ─────────────────
    private function notify(int $toUserId, int $fromUserId, string $type, array $extra = []): void
    {
        if ($this->fcm === null) return;
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
            } else { // accept
                $title = 'Arkadaşlık isteği kabul edildi';
                $body  = "$name isteğini kabul etti.";
                $kind  = 'friend_accept';
            }
            $data['type'] = $kind;

            $this->fcm->sendToUser($this->db, $toUserId, $title, $body, $data);
        } catch (Throwable $e) {
            // Push isteğe bağlıdır; hata olsa bile arkadaşlık işlemi başarılı sayılır.
            cinema_error('[Non-blocking] Social push notification failed: ' . $e->getMessage(), $toUserId);
        }
    }

    // ─── POST /social/profile/setup ─────────────────────────────────────────
    public function setupProfile(int $uid, array $in): void
    {
        $username = strtolower(trim((string) ($in['username'] ?? '')));
        $isPublic = isset($in['is_public']) ? ((int) $in['is_public'] === 1 ? 1 : 0) : 1;

        if ($username === '') {
            fail(422, 'Kullanıcı adı boş bırakılamaz.');
        }

        // Alfasayısal karakterler ve alt çizgi kontrolü, uzunluk 3-30
        if (!preg_match('/^[a-z0-9_]{3,30}$/', $username)) {
            fail(422, 'Kullanıcı adı 3-30 karakter olmalı ve sadece harf, sayı veya alt çizgi içermelidir.');
        }

        // Kendisi hariç bu kullanıcı adını alan başkası var mı kontrol et
        $st = $this->db->prepare('SELECT id FROM users WHERE username = ? AND id != ?');
        $st->execute([$username, $uid]);
        if ($st->fetch()) {
            fail(409, 'Bu kullanıcı adı zaten alınmış.');
        }

        // Güncelle
        $up = $this->db->prepare('UPDATE users SET username = ?, is_public = ?, updated_at = ? WHERE id = ?');
        $up->execute([$username, $isPublic, now_ms(), $uid]);

        json_out(200, ['ok' => true, 'username' => $username, 'is_public' => $isPublic]);
    }

    // ─── POST /social/dna ───────────────────────────────────────────────────
    // Cihazın ürettiği Sinema DNA snapshot'ını saklar (public web kartı için).
    // Algoritma sunucuda tekrarlanmaz; yalnızca hazır snapshot depolanır.
    public function publishTasteDna(int $uid, array $in): void
    {
        $dna = $in['dna'] ?? null;
        if (!is_array($dna)) {
            fail(422, 'Geçersiz DNA verisi.');
        }

        $json = json_encode($dna, JSON_UNESCAPED_UNICODE);
        // Kötüye kullanıma karşı boyut tavanı — normal snapshot ~1KB'dir.
        if ($json === false || strlen($json) > 8192) {
            fail(422, 'DNA verisi geçersiz ya da çok büyük.');
        }

        $up = $this->db->prepare(
            'UPDATE users SET taste_dna = ?, taste_dna_at = ? WHERE id = ?'
        );
        $up->execute([$json, now_ms(), $uid]);

        json_out(200, ['ok' => true]);
    }

    // ─── POST /social/friends/request ───────────────────────────────────────
    public function sendFriendRequest(int $uid, array $in): void
    {
        $search = trim((string) ($in['search_query'] ?? ''));
        if ($search === '') fail(422, 'Arama sorgusu gerekli.');

        // Kendisini eklemesini engelle
        $st = $this->db->prepare('SELECT id, email, username FROM users WHERE (email = ? OR username = ?) AND id != ?');
        $st->execute([$search, $search, $uid]);
        $target = $st->fetch();

        if (!$target) {
            fail(404, 'Kullanıcı bulunamadı.');
        }

        $friendId = (int) $target['id'];

        // Zaten arkadaş veya istek var mı kontrol et
        $check = $this->db->prepare('SELECT status FROM friends WHERE user_id = ? AND friend_id = ?');
        $check->execute([$uid, $friendId]);
        $rel = $check->fetch();

        if ($rel) {
            if ($rel['status'] === 'accepted') {
                fail(409, 'Zaten arkadaşsınız.');
            } else {
                fail(409, 'Gönderilmiş bir arkadaşlık isteği zaten mevcut.');
            }
        }

        // Karşı taraftan bize gelen bir istek var mı kontrolü (varsa otomatik kabul et)
        $checkReverse = $this->db->prepare('SELECT status FROM friends WHERE user_id = ? AND friend_id = ?');
        $checkReverse->execute([$friendId, $uid]);
        $revRel = $checkReverse->fetch();

        $t = now_ms();
        if ($revRel && $revRel['status'] === 'pending') {
            $this->db->beginTransaction();
            try {
                // Karşılıklı onay durumuna getir
                $up = $this->db->prepare('UPDATE friends SET status = \'accepted\', updated_at = ? WHERE user_id = ? AND friend_id = ?');
                $up->execute([$t, $friendId, $uid]);

                $ins = $this->db->prepare('INSERT INTO friends (user_id, friend_id, status, created_at, updated_at) VALUES (?, ?, \'accepted\', ?, ?)');
                $ins->execute([$uid, $friendId, $t, $t]);

                $this->db->commit();
                // Karşı taraf (orijinal isteği gönderen) kabul bildirimi alır.
                $this->notify($friendId, $uid, 'accept');
                json_out(200, ['ok' => true, 'status' => 'accepted', 'message' => 'Arkadaşlık isteği karşılıklı olarak kabul edildi.']);
                return;
            } catch (Throwable $e) {
                $this->db->rollBack();
                throw $e;
            }
        }

        // Normal istek oluştur
        $ins = $this->db->prepare('INSERT INTO friends (user_id, friend_id, status, created_at, updated_at) VALUES (?, ?, \'pending\', ?, ?)');
        $ins->execute([$uid, $friendId, $t, $t]);

        // Hedef kullanıcıya yeni istek bildirimi.
        $this->notify($friendId, $uid, 'request');
        json_out(200, ['ok' => true, 'status' => 'pending', 'message' => 'Arkadaşlık isteği gönderildi.']);
    }

    // ─── POST /social/friends/accept ────────────────────────────────────────
    public function acceptFriendRequest(int $uid, array $in): void
    {
        $friendId = (int) ($in['friend_id'] ?? 0);
        if ($friendId === 0) fail(422, 'friend_id gerekli.');

        // Bize gelen pending istek var mı doğrula
        $st = $this->db->prepare('SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ? AND status = \'pending\'');
        $st->execute([$friendId, $uid]);
        if (!$st->fetch()) {
            fail(404, 'Onaylanacak arkadaşlık isteği bulunamadı.');
        }

        $this->db->beginTransaction();
        try {
            $t = now_ms();
            // İsteği kabul et
            $up = $this->db->prepare('UPDATE friends SET status = \'accepted\', updated_at = ? WHERE user_id = ? AND friend_id = ?');
            $up->execute([$t, $friendId, $uid]);

            // Karşılıklı kayıt var mı kontrol et
            $check = $this->db->prepare('SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?');
            $check->execute([$uid, $friendId]);
            if ($check->fetch()) {
                $up2 = $this->db->prepare('UPDATE friends SET status = \'accepted\', updated_at = ? WHERE user_id = ? AND friend_id = ?');
                $up2->execute([$t, $uid, $friendId]);
            } else {
                $ins = $this->db->prepare(
                    'INSERT INTO friends (user_id, friend_id, status, created_at, updated_at)
                     VALUES (?, ?, \'accepted\', ?, ?)'
                );
                $ins->execute([$uid, $friendId, $t, $t]);
            }

            $this->db->commit();
            // İsteği gönderen kullanıcı, kabul edildiği bilgisini alır.
            $this->notify($friendId, $uid, 'accept');
            json_out(200, ['ok' => true]);
        } catch (Throwable $e) {
            $this->db->rollBack();
            throw $e;
        }
    }

    // ─── POST /social/friends/reject ────────────────────────────────────────
    public function rejectFriendRequest(int $uid, array $in): void
    {
        $friendId = (int) ($in['friend_id'] ?? 0);
        if ($friendId === 0) fail(422, 'friend_id gerekli.');

        // İki yöndeki ilişkileri de sil
        $del = $this->db->prepare('DELETE FROM friends WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)');
        $del->execute([$uid, $friendId, $friendId, $uid]);

        json_out(200, ['ok' => true]);
    }

    // ─── GET /social/friends ────────────────────────────────────────────────
    public function getFriends(int $uid): void
    {
        // 1. Onaylanmış arkadaşlar (accepted)
        $st1 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username, u.email
             FROM friends f
             JOIN users u ON f.friend_id = u.id
             WHERE f.user_id = ? AND f.status = \'accepted\''
        );
        $st1->execute([$uid]);
        $accepted = $st1->fetchAll();

        // 2. Gelen istekler (friend_id = biz, status = pending)
        $st2 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username, u.email
             FROM friends f
             JOIN users u ON f.user_id = u.id
             WHERE f.friend_id = ? AND f.status = \'pending\''
        );
        $st2->execute([$uid]);
        $pendingReceived = $st2->fetchAll();

        // 3. Gönderilen istekler (user_id = biz, status = pending)
        $st3 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username, u.email
             FROM friends f
             JOIN users u ON f.friend_id = u.id
             WHERE f.user_id = ? AND f.status = \'pending\''
        );
        $st3->execute([$uid]);
        $pendingSent = $st3->fetchAll();

        json_out(200, [
            'friends' => $accepted,
            'pending_received' => $pendingReceived,
            'pending_sent' => $pendingSent
        ]);
    }

    // ─── GET /social/friends/activity ───────────────────────────────────────
    public function getActivityFeed(int $uid, ?int $friendId = null): void
    {
        // Gizlenen (is_hidden=1) yorum metni akışa sızmaz; puan aktivitesi kalır.
        $sql = 'SELECT r.movie_id, r.is_tv, r.rating, r.title, r.poster_path, r.updated_at,
                       CASE WHEN r.is_hidden = 1 THEN NULL ELSE r.comment END as comment,
                       r.is_spoiler,
                       u.id as friend_id, u.display_name as friend_name, u.username as friend_username
                FROM friends f
                JOIN users u ON f.friend_id = u.id
                JOIN ratings r ON f.friend_id = r.user_id
                WHERE f.user_id = ? AND f.status = \'accepted\' AND r.is_private = 0';
        
        $params = [$uid];
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


    // ─── GET /social/match/watchlist-intersection/{friend_id} ───────────────
    public function getWatchlistIntersection(int $uid, int $friendId): void
    {
        // Arkadaşlık ilişkisini doğrula
        $check = $this->db->prepare('SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ? AND status = \'accepted\'');
        $check->execute([$uid, $friendId]);
        if (!$check->fetch()) {
            fail(403, 'Bu kullanıcının ortak listesine erişim yetkiniz yok.');
        }

        // Watchlist kesişimini al
        $st = $this->db->prepare(
            'SELECT w1.id, w1.is_tv, w1.title, w1.poster_path, w1.backdrop_path, w1.overview, w1.vote_average, w1.release_date, w1.genre_ids
             FROM watchlist w1
             JOIN watchlist w2 ON w1.id = w2.id AND w1.is_tv = w2.is_tv
             WHERE w1.user_id = ? AND w2.user_id = ?
               AND w1.deleted = 0 AND w2.deleted = 0
             ORDER BY w1.created_at DESC'
        );
        $st->execute([$uid, $friendId]);
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

        $mine   = $this->fetchRatingsMap($uid);
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

        json_out(200, [
            'score'            => max(0, min(100, $score)),
            'common_count'     => $common,
            'both_loved'       => $bothLoved,
            'agreement'        => round($agreement, 4),
            'genre_similarity' => round($genreSim, 4),
            // Skor güvenilir mi? İki tarafta da veri yoksa UI rozeti gizleyebilir.
            'has_data'         => $common > 0 || (!empty($mine) && !empty($theirs)),
        ]);
    }

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

    // ─── Yardımcılar (uyum skoru) ───────────────────────────────────────────

    /** accepted arkadaşlık yoksa 403 ile sonlanır. */
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

    /** Kullanıcının puanlarını "movie_603" / "tv_1399" anahtarlı haritaya çevirir. */
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

    /** Puanlardan tür ağırlık vektörü üretir (istemci PrefsService ile aynı ağırlıklar). */
    private function genreVector(array $ratingsMap): array
    {
        static $weights = [3 => 2.0, 2 => 1.0, 1 => -1.0, 0 => -2.0];
        $v = [];
        foreach ($ratingsMap as $r) {
            $w = $weights[$r['rating']] ?? 0.0;
            if ($w === 0.0) continue;
            foreach ($r['genres'] as $g) {
                if (is_int($g)) $v[$g] = ($v[$g] ?? 0.0) + $w;
            }
        }
        return $v;
    }

    /** İki seyrek vektörün kosinüs benzerliği (-1..1). Boş vektörde 0. */
    private function cosine(array $a, array $b): float
    {
        if (!$a || !$b) return 0.0;
        $dot = 0.0;
        foreach ($a as $k => $va) {
            if (isset($b[$k])) $dot += $va * $b[$k];
        }
        $na = sqrt(array_sum(array_map(fn($x) => $x * $x, $a)));
        $nb = sqrt(array_sum(array_map(fn($x) => $x * $x, $b)));
        if ($na == 0.0 || $nb == 0.0) return 0.0;
        return $dot / ($na * $nb);
    }

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
    private const AUTO_HIDE_THRESHOLD = 3;
    private const REPORT_REASONS = ['profanity', 'spam', 'spoiler', 'harassment', 'other'];

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
                AND deleted = 0 AND comment IS NOT NULL AND comment <> \'\''
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
            $up = $this->db->prepare(
                'UPDATE ratings SET is_hidden = 1 WHERE user_id = ? AND movie_id = ? AND is_tv = ?'
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
             'SELECT title, poster_path, movie_id, is_tv FROM ratings
              WHERE user_id = ? AND rating >= 2 AND deleted = 0 AND is_private = 0 AND poster_path IS NOT NULL
              ORDER BY rating DESC, updated_at DESC
              LIMIT 10'
        );

        $profiles = [];
        foreach ($st->fetchAll() as $u) {
            $posterStmt->execute([(int) $u['id']]);
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

        json_out(200, ['signals' => $signals]);
    }

    // ─── GET /download (Halka Açık İndirme Sayfası) ──────────────────────────
    public function renderDownloadPage(): void
    {
        $this->webRenderer()->renderDownloadPage();
    }

    private function webRenderer(): SocialWebRenderer
    {
        return $this->webRenderer ??= new SocialWebRenderer($this->db);
    }
}
