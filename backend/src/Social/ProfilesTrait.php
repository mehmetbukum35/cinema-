<?php
declare(strict_types=1);

trait SocialProfilesTrait
{
    // ─── POST /social/profile/setup ─────────────────────────────────────────
    /** @param array<string, mixed> $in */
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

        // UNIQUE constraint ihlalini yakala; SELECT→UPDATE arasında race olsa
        // bile veritabanı ikinci yazımı reddeder (409 döneriz).
        try {
            $up = $this->db->prepare(
                'UPDATE users SET username = ?, is_public = ?, updated_at = ?
                  WHERE id = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM users u2
                         WHERE u2.username = ? AND u2.id != ?
                    )'
            );
            $up->execute([$username, $isPublic, now_ms(), $uid, $username, $uid]);
        } catch (\PDOException $e) {
            // UNIQUE constraint violation (SQLSTATE 23*)
            if (str_starts_with((string) $e->getCode(), '23')) {
                fail(409, 'Bu kullanıcı adı zaten alınmış.', 'username_taken');
            }
            throw $e;
        }

        if ($up->rowCount() === 0) {
            // MySQL/SQLite: değerler aynıysa rowCount=0 — false username_taken verme.
            $cur = $this->db->prepare('SELECT username, is_public FROM users WHERE id = ?');
            $cur->execute([$uid]);
            $row = $cur->fetch();
            if (!$row) {
                fail(404, 'Kullanıcı bulunamadı.');
            }
            if (
                (string) $row['username'] === $username
                && (int) $row['is_public'] === $isPublic
            ) {
                json_out(200, ['ok' => true, 'username' => $username, 'is_public' => $isPublic]);
            }
            fail(409, 'Bu kullanıcı adı zaten alınmış.', 'username_taken');
        }

        $this->invalidateTopProfilesCache();

        json_out(200, ['ok' => true, 'username' => $username, 'is_public' => $isPublic]);
    }

    // ─── POST /social/dna ───────────────────────────────────────────────────
    // Cihazın ürettiği Sinema DNA snapshot'ını saklar (public web kartı için).
    // Algoritma sunucuda tekrarlanmaz; yalnızca hazır snapshot depolanır.
    /** @param array<string, mixed> $in */
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
}
