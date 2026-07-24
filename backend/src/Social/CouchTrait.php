<?php
declare(strict_types=1);

/**
 * "Birlikte Seç" — canlı kanepe modu. İki arkadaş kendi telefonlarından aynı
 * desteyi oylar; ilk karşılıklı beğenide oturum 'matched' olur. Gerçek zaman
 * websocket'le değil kısa aralıklı poll ile sağlanır (paylaşımlı hosting).
 *
 * Gizlilik kuralı: bir katılımcı karşı tarafın TEK TEK oylarını göremez —
 * yalnızca kaç kart oyladığını (their_progress) görür. Aksi halde "önden
 * bakıp ona göre oylama" ile oyunun anlamı bozulurdu.
 */
trait SocialCouchTrait
{
    private const COUCH_MIN_DECK = 5;
    private const COUCH_MAX_DECK = 30;
    /** Katılımcı başına oturum yaşam alanları. */
    private const COUCH_OPEN_STATUSES = ['pending', 'active'];

    // ─── POST /social/couch/create ──────────────────────────────────────────
    // Girdi: { friend_id, deck: [{movie_id,is_tv,title,poster_path,vote_average}] }
    // Desteyi HOST istemcisi kurar (ortak izleme listesi + öneri motoru);
    // sunucu yalnızca doğrular, kırpar ve saklar.
    public function createCouchSession(int $uid, array $in): void
    {
        $friendId = (int) ($in['friend_id'] ?? 0);
        if ($friendId <= 0) fail(422, 'friend_id gerekli.');
        if ($friendId === $uid) fail(422, 'Kendinle oturum açamazsın.');
        $this->assertFriendship($uid, $friendId, 'Yalnızca arkadaşlarınla Birlikte Seç oynayabilirsin.');

        $rawDeck = $in['deck'] ?? null;
        if (!is_array($rawDeck)) fail(422, 'deck gerekli.');

        $deck = [];
        $seen = [];
        foreach ($rawDeck as $item) {
            if (!is_array($item)) continue;
            $movieId = (int) ($item['movie_id'] ?? 0);
            $title = trim((string) ($item['title'] ?? ''));
            if ($movieId <= 0 || $title === '') continue;
            $isTv = !empty($item['is_tv']) ? 1 : 0;
            $key = ($isTv ? 'tv_' : 'movie_') . $movieId;
            if (isset($seen[$key])) continue;
            $seen[$key] = true;
            // Yalnızca gereken alanlar saklanır (satır boyutu sınırlı kalsın).
            $deck[] = [
                'movie_id'     => $movieId,
                'is_tv'        => $isTv,
                'title'        => mb_substr($title, 0, 256),
                'poster_path'  => mb_substr(trim((string) ($item['poster_path'] ?? '')), 0, 255) ?: null,
                'vote_average' => round((float) ($item['vote_average'] ?? 0), 1),
            ];
            if (count($deck) >= self::COUCH_MAX_DECK) break;
        }
        if (count($deck) < self::COUCH_MIN_DECK) {
            fail(422, 'Deste çok küçük (en az ' . self::COUCH_MIN_DECK . ' yapım).');
        }

        $t = now_ms();
        // Tek aktif oturum kuralı: her iki katılımcının da açık oturumları
        // kapatılır — eski bir davet yenisinin önüne geçmesin.
        // Transaction: eşzamanlı create'lerde çift pending/active satırı oluşmasın.
        $this->db->beginTransaction();
        try {
            $close = $this->db->prepare(
                "UPDATE couch_sessions SET status = 'cancelled', updated_at = ?
                  WHERE (host_id IN (?, ?) OR guest_id IN (?, ?))
                    AND status IN ('pending', 'active')"
            );
            $close->execute([$t, $uid, $friendId, $uid, $friendId]);

            $ins = $this->db->prepare(
                'INSERT INTO couch_sessions
                   (host_id, guest_id, status, deck, host_votes, guest_votes, created_at, updated_at)
                 VALUES (?, ?, \'pending\', ?, ?, ?, ?, ?)'
            );
            $ins->execute([
                $uid,
                $friendId,
                json_encode($deck, JSON_UNESCAPED_UNICODE),
                '{}',
                '{}',
                $t,
                $t,
            ]);
            $sessionId = (int) $this->db->lastInsertId();
            $this->db->commit();
        } catch (\Throwable $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            throw $e;
        }

        $this->notify($friendId, $uid, 'couch_invite', ['session_id' => $sessionId]);
        json_out(200, ['session' => $this->couchPayload($this->loadCouchSession($sessionId), $uid)]);
    }

    // ─── GET /social/couch/active ───────────────────────────────────────────
    // Katılımcısı olduğum en güncel canlı oturum (pending/active/matched).
    // 'matched' da döner ki karşı taraf kutlama ekranını kaçırmasın; istemci
    // gösterdikten sonra oturumu kapatır (finish).
    public function getActiveCouchSession(int $uid): void
    {
        $st = $this->db->prepare(
            "SELECT * FROM couch_sessions
              WHERE (host_id = ? OR guest_id = ?)
                AND status IN ('pending', 'active', 'matched')
              ORDER BY updated_at DESC
              LIMIT 1"
        );
        $st->execute([$uid, $uid]);
        $row = $st->fetch();
        if (!$row) {
            json_out(200, ['session' => null]);
        }
        $this->assertCouchFriendshipForRow($row, $uid);
        json_out(200, ['session' => $this->couchPayload($row, $uid)]);
    }

    // ─── GET /social/couch/{id} (poll ucu) ──────────────────────────────────
    public function getCouchSession(int $uid, int $sessionId): void
    {
        $row = $this->requireCouchParticipant($uid, $sessionId);
        $row = $this->activateIfGuestArrived($row, $uid);
        // Emniyet ağı: eşzamanlı son oylarda vote ucundaki tespit kaçırdıysa
        // poll yakalar (bkz. resolveCouchOutcome).
        $row = $this->resolveCouchOutcome($row);
        json_out(200, ['session' => $this->couchPayload($row, $uid)]);
    }

    // ─── POST /social/couch/{id}/vote ───────────────────────────────────────
    // Girdi: { movie_id, is_tv, liked }. Oy kullanıcının KENDİ kolonuna yazılır
    // (host_votes/guest_votes) — eşzamanlı iki oy birbirini ezemez.
    public function voteCouchSession(int $uid, int $sessionId, array $in): void
    {
        $movieId = (int) ($in['movie_id'] ?? 0);
        if ($movieId <= 0) fail(422, 'movie_id gerekli.');
        $isTv = !empty($in['is_tv']) ? 1 : 0;
        $liked = !empty($in['liked']);

        $this->db->beginTransaction();
        try {
            // Lock the JSON vote row before read-modify-write. Otherwise two
            // devices belonging to the same participant can overwrite each
            // other's vote.
            $row = $this->loadCouchSession($sessionId, true);
            if ((int) $row['host_id'] !== $uid && (int) $row['guest_id'] !== $uid) {
                fail(403, 'Bu oturuma erişim yetkin yok.');
            }
            $this->assertCouchFriendshipForRow($row, $uid);
            if ($row['status'] === 'cancelled' || $row['status'] === 'ended') {
                fail(409, 'Oturum sona erdi.');
            }
            if ($row['status'] !== 'matched') {
                $row = $this->activateIfGuestArrived($row, $uid);

                $key = ($isTv ? 'tv_' : 'movie_') . $movieId;
                $deckKeys = array_map(
                    fn (array $d) => ($d['is_tv'] ? 'tv_' : 'movie_') . $d['movie_id'],
                    json_decode((string) $row['deck'], true) ?: []
                );
                if (!in_array($key, $deckKeys, true)) {
                    fail(422, 'Bu yapım destede yok.');
                }

                $isHost = ((int) $row['host_id']) === $uid;
                $col = $isHost ? 'host_votes' : 'guest_votes';
                $votes = json_decode((string) $row[$col], true) ?: [];
                $votes[$key] = $liked;

                $up = $this->db->prepare(
                    "UPDATE couch_sessions SET `$col` = ?, updated_at = ? WHERE id = ?"
                );
                $up->execute([json_encode($votes), now_ms(), $sessionId]);
                $row = $this->resolveCouchOutcome($this->loadCouchSession($sessionId), $uid);
            }
            $this->db->commit();
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
        json_out(200, ['session' => $this->couchPayload($row, $uid)]);
    }

    // ─── POST /social/couch/{id}/cancel ─────────────────────────────────────
    // Eşleşmiş oturumda 'kapat' = finish (ended); açık oturumda iptal.
    public function cancelCouchSession(int $uid, int $sessionId): void
    {
        $row = $this->requireCouchParticipant($uid, $sessionId);
        $newStatus = $row['status'] === 'matched' ? 'ended' : 'cancelled';
        if ($row['status'] === 'ended' || $row['status'] === 'cancelled') {
            $newStatus = $row['status'];
        } else {
            $up = $this->db->prepare(
                'UPDATE couch_sessions SET status = ?, updated_at = ? WHERE id = ?'
            );
            $up->execute([$newStatus, now_ms(), $sessionId]);
        }
        json_out(200, ['ok' => true, 'status' => $newStatus]);
    }

    // ─── Yardımcılar ────────────────────────────────────────────────────────

    private function loadCouchSession(int $sessionId, bool $forUpdate = false): array
    {
        $driver = (string) $this->db->getAttribute(PDO::ATTR_DRIVER_NAME);
        $lock = $forUpdate && $driver !== 'sqlite' ? ' FOR UPDATE' : '';
        $st = $this->db->prepare('SELECT * FROM couch_sessions WHERE id = ?' . $lock);
        $st->execute([$sessionId]);
        $row = $st->fetch();
        if (!$row) fail(404, 'Oturum bulunamadı.');
        return $row;
    }

    private function requireCouchParticipant(int $uid, int $sessionId): array
    {
        $row = $this->loadCouchSession($sessionId);
        if ((int) $row['host_id'] !== $uid && (int) $row['guest_id'] !== $uid) {
            fail(403, 'Bu oturuma erişim yetkin yok.');
        }
        $this->assertCouchFriendshipForRow($row, $uid);
        return $row;
    }

    private function assertCouchFriendshipForRow(array $row, int $uid): void
    {
        $friendId = (int) $row['host_id'] === $uid
            ? (int) $row['guest_id']
            : (int) $row['host_id'];
        $this->assertFriendship(
            $uid,
            $friendId,
            'Bu Birlikte Seç oturumuna erişim yetkiniz yok.'
        );
    }

    private function cancelCouchSessionsBetween(int $uid, int $friendId): void
    {
        $cancel = $this->db->prepare(
            "UPDATE couch_sessions SET status = 'cancelled', updated_at = ?
              WHERE ((host_id = ? AND guest_id = ?) OR (host_id = ? AND guest_id = ?))
                AND status IN ('pending', 'active', 'matched')"
        );
        $cancel->execute([now_ms(), $uid, $friendId, $friendId, $uid]);
    }

    /** Misafirin ilk teması oturumu pending → active taşır. */
    private function activateIfGuestArrived(array $row, int $uid): array
    {
        if ($row['status'] === 'pending' && (int) $row['guest_id'] === $uid) {
            $up = $this->db->prepare(
                "UPDATE couch_sessions SET status = 'active', updated_at = ? WHERE id = ? AND status = 'pending'"
            );
            $up->execute([now_ms(), (int) $row['id']]);
            $row['status'] = 'active';
        }
        return $row;
    }

    /**
     * Oturum sonucunu çözer: karşılıklı beğeni varsa 'matched' (+ karşı tarafa
     * push), iki taraf da desteyi bitirmiş ve eşleşme yoksa 'ended'.
     *
     * @param int|null $exceptUserId Oyunu tetikleyen kullanıcı — zaten ekranda;
     *                               push yalnızca karşı tarafa gider.
     */
    private function resolveCouchOutcome(array $row, ?int $exceptUserId = null): array
    {
        if ($row['status'] !== 'active' && $row['status'] !== 'pending') {
            return $row;
        }
        $deck = json_decode((string) $row['deck'], true) ?: [];
        $hostVotes = json_decode((string) $row['host_votes'], true) ?: [];
        $guestVotes = json_decode((string) $row['guest_votes'], true) ?: [];

        // Deste sırasına göre İLK karşılıklı beğeni kazanır (deterministik).
        foreach ($deck as $item) {
            $key = ($item['is_tv'] ? 'tv_' : 'movie_') . $item['movie_id'];
            if (($hostVotes[$key] ?? false) === true && ($guestVotes[$key] ?? false) === true) {
                $up = $this->db->prepare(
                    "UPDATE couch_sessions SET status = 'matched', matched_key = ?, updated_at = ?
                      WHERE id = ? AND status IN ('pending', 'active')"
                );
                $up->execute([$key, now_ms(), (int) $row['id']]);
                if ($up->rowCount() > 0) {
                    // Eşleşmeyi çözen istek zaten kendi ekranında görecek;
                    // push, KARŞI tarafı uygulamaya geri çağırır. Poll yolu
                    // (exceptUserId=null) her iki tarafa da bildirebilir.
                    $hostId = (int) $row['host_id'];
                    $guestId = (int) $row['guest_id'];
                    $payload = [
                        'title'      => (string) $item['title'],
                        'session_id' => (int) $row['id'],
                    ];
                    if ($exceptUserId !== $hostId) {
                        $this->notify($hostId, $guestId, 'couch_match', $payload);
                    }
                    if ($exceptUserId !== $guestId) {
                        $this->notify($guestId, $hostId, 'couch_match', $payload);
                    }
                }
                $row['status'] = 'matched';
                $row['matched_key'] = $key;
                return $row;
            }
        }

        if (count($hostVotes) >= count($deck) && count($guestVotes) >= count($deck)) {
            $up = $this->db->prepare(
                "UPDATE couch_sessions SET status = 'ended', updated_at = ?
                  WHERE id = ? AND status IN ('pending', 'active')"
            );
            $up->execute([now_ms(), (int) $row['id']]);
            $row['status'] = 'ended';
        }
        return $row;
    }

    public function getUsedCouchMovies(int $uid, int $friendId): void
    {
        $this->assertFriendship($uid, $friendId, 'Yalnızca arkadaşlarınla oynayabilirsin.');

        $st = $this->db->prepare(
            "SELECT deck FROM couch_sessions
              WHERE ((host_id = ? AND guest_id = ?) OR (host_id = ? AND guest_id = ?))
                AND status IN ('cancelled', 'ended', 'matched')
              ORDER BY id DESC
              LIMIT 5"
        );
        $st->execute([$uid, $friendId, $friendId, $uid]);

        $used = [];
        foreach ($st->fetchAll() as $row) {
            $deck = json_decode((string) $row['deck'], true) ?: [];
            foreach ($deck as $item) {
                $isTv = !empty($item['is_tv']) ? 1 : 0;
                $key = ($isTv ? 'tv_' : 'movie_') . $item['movie_id'];
                $used[] = $key;
            }
        }

        $used = array_values(array_unique($used));
        json_out(200, ['used_keys' => $used]);
    }

    /** İstemciye dönen oturum görünümü ([uid] perspektifinden). */
    private function couchPayload(array $row, int $uid): array
    {
        $isHost = ((int) $row['host_id']) === $uid;
        $otherId = $isHost ? (int) $row['guest_id'] : (int) $row['host_id'];

        $st = $this->db->prepare('SELECT display_name, username FROM users WHERE id = ?');
        $st->execute([$otherId]);
        $other = $st->fetch() ?: [];

        $deck = json_decode((string) $row['deck'], true) ?: [];
        $myVotes = json_decode((string) $row[$isHost ? 'host_votes' : 'guest_votes'], true) ?: [];
        $theirVotes = json_decode((string) $row[$isHost ? 'guest_votes' : 'host_votes'], true) ?: [];

        $matched = null;
        if (!empty($row['matched_key'])) {
            foreach ($deck as $item) {
                $key = ($item['is_tv'] ? 'tv_' : 'movie_') . $item['movie_id'];
                if ($key === $row['matched_key']) {
                    $matched = $item;
                    break;
                }
            }
        }

        return [
            'id'             => (int) $row['id'],
            'status'         => (string) $row['status'],
            'is_host'        => $isHost,
            'friend'         => [
                'id'           => $otherId,
                'display_name' => $other['display_name'] ?? null,
                'username'     => $other['username'] ?? null,
            ],
            'deck'           => $deck,
            // (object): PHP boş assoc diziyi JSON'a `[]` (liste!) yazar; istemci
            // Map beklediği için oturumun İLK halinde tip hatası patlıyordu.
            'my_votes'       => (object) $myVotes,
            // Karşı tarafın oy İÇERİĞİ bilinçli olarak dönülmez (hile önlenir);
            // yalnızca ilerleme sayısı döner.
            'their_progress' => count($theirVotes),
            'matched'        => $matched,
            'created_at'     => (int) $row['created_at'],
        ];
    }
}
