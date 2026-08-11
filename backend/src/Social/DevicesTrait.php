<?php
declare(strict_types=1);

trait SocialDevicesTrait
{
    // ─── POST /social/device/register ───────────────────────────────────────
    // İstemci FCM token'ını kaydeder/günceller. Token tekildir (PK): aynı cihaz
    // başka bir hesaba geçtiyse user_id güncellenir, çift kayıt oluşmaz.
    /** @param array<string, mixed> $in */
    public function registerDevice(int $uid, array $in): void
    {
        $token = trim((string) ($in['token'] ?? ''));
        if ($token === '') fail(422, 'token gerekli.');
        $platform = substr(trim((string) ($in['platform'] ?? '')), 0, 20) ?: null;

        $t = now_ms();
        $driver = (string) $this->db->getAttribute(PDO::ATTR_DRIVER_NAME);
        try {
            if ($driver === 'mysql') {
                $ups = $this->db->prepare(
                    'INSERT INTO device_tokens (user_id, token, platform, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?)
                     ON DUPLICATE KEY UPDATE user_id = VALUES(user_id),
                       platform = VALUES(platform), updated_at = VALUES(updated_at)'
                );
                $ups->execute([$uid, $token, $platform, $t, $t]);
            } else {
                // SQLite
                $ups = $this->db->prepare(
                    'INSERT INTO device_tokens (user_id, token, platform, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?)
                     ON CONFLICT(token) DO UPDATE SET
                       user_id = excluded.user_id,
                       platform = excluded.platform,
                       updated_at = excluded.updated_at'
                );
                $ups->execute([$uid, $token, $platform, $t, $t]);
            }
        } catch (PDOException $e) {
            // SELECT→INSERT yarışı: UNIQUE ihlali → UPDATE.
            if (!str_starts_with((string) $e->getCode(), '23')
                && (int) ($e->errorInfo[1] ?? 0) !== 1062
                && !str_contains($e->getMessage(), 'UNIQUE')) {
                throw $e;
            }
            $up = $this->db->prepare(
                'UPDATE device_tokens SET user_id = ?, platform = ?, updated_at = ? WHERE token = ?'
            );
            $up->execute([$uid, $platform, $t, $token]);
        }
        json_out(200, ['ok' => true]);
    }

    // ─── POST /social/device/unregister (çıkış yaparken) ────────────────────
    /** @param array<string, mixed> $in */
    public function unregisterDevice(int $uid, array $in): void
    {
        $token = trim((string) ($in['token'] ?? ''));
        if ($token === '') fail(422, 'token gerekli.');
        $del = $this->db->prepare('DELETE FROM device_tokens WHERE token = ? AND user_id = ?');
        $del->execute([$token, $uid]);
        json_out(200, ['ok' => true]);
    }
}
