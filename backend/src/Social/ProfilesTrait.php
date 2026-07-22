<?php
declare(strict_types=1);

trait SocialProfilesTrait
{
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
        $this->invalidateTopProfilesCache();

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
}
