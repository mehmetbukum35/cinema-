<?php
declare(strict_types=1);

trait SocialFriendsTrait
{
    // ─── POST /social/friends/request ───────────────────────────────────────
    public function sendFriendRequest(int $uid, array $in): void
    {
        $search = trim((string) ($in['search_query'] ?? ''));
        if ($search === '') fail(422, 'Arama sorgusu gerekli.');

        // E-postalar kayıt sırasında küçük harfe normalize edilir. Kullanıcı adı
        // özgün değerini korurken e-posta karşılaştırmasını da aynı sözleşmeye
        // çekmek SQLite ve case-sensitive MySQL kurulumlarında davranış farkını önler.
        $emailSearch = strtolower($search);

        // Kendisini eklemesini engelle
        $st = $this->db->prepare('SELECT id, email, username FROM users WHERE (email = ? OR username = ?) AND id != ?');
        $st->execute([$emailSearch, $search, $uid]);
        $target = $st->fetch();

        if (!$target) {
            fail(404, 'Kullanıcı bulunamadı.');
        }

        $friendId = (int) $target['id'];

        // Engel kontrolü (iki yönlü): engellenen kişi engelleyene istek atamaz,
        // engelleyen de engellediğine atamaz. Engellendiğini belli etmemek için
        // "bulunamadı" ile aynı yanıt döner (taciz edenin doğrulama yapmasını önler).
        $blk = $this->db->prepare(
            'SELECT 1 FROM user_blocks
              WHERE (user_id = ? AND blocked_user_id = ?)
                 OR (user_id = ? AND blocked_user_id = ?)'
        );
        $blk->execute([$uid, $friendId, $friendId, $uid]);
        if ($blk->fetch()) {
            fail(404, 'Kullanıcı bulunamadı.');
        }

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
        // Not: u.email BİLEREK seçilmiyor. Yanıta eklemek, kullanıcı adı bilinen
        // herkesin e-postasını toplamaya izin veriyordu (istek at → pending_sent
        // içinden e-postayı oku). İstemci bu alanı hiçbir yerde göstermiyor.

        // 1. Onaylanmış arkadaşlar (accepted)
        $st1 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username
             FROM friends f
             JOIN users u ON f.friend_id = u.id
             WHERE f.user_id = ? AND f.status = \'accepted\''
        );
        $st1->execute([$uid]);
        $accepted = $st1->fetchAll();

        // 2. Gelen istekler (friend_id = biz, status = pending)
        $st2 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username
             FROM friends f
             JOIN users u ON f.user_id = u.id
             WHERE f.friend_id = ? AND f.status = \'pending\''
        );
        $st2->execute([$uid]);
        $pendingReceived = $st2->fetchAll();

        // 3. Gönderilen istekler (user_id = biz, status = pending)
        $st3 = $this->db->prepare(
            'SELECT u.id, u.display_name, u.username
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
}
