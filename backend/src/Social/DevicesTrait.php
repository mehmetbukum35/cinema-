<?php
declare(strict_types=1);

trait SocialDevicesTrait
{
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
}
