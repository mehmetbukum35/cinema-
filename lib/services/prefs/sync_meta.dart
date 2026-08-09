import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PrefsSyncMeta {
  static const _keyLastSyncTime = 'sync_last_time';
  static const _keyLastPushTime = 'sync_last_push_time';
  static const _keySyncDeviceId = 'sync_device_id';

  static Future<int> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSyncTime) ?? 0;
  }

  static Future<void> setLastSyncTime(int time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncTime, time);
  }

  /// Push imleci: CİHAZ saatiyle tutulur (pull imleci ise sunucu saatiyle).
  /// Eski kurulumlarda anahtar yoksa mevcut davranışı korumak için
  /// sync_last_time'a düşer.
  static Future<int> getLastPushTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastPushTime) ??
        prefs.getInt(_keyLastSyncTime) ??
        0;
  }

  static Future<void> setLastPushTime(int time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastPushTime, time);
  }

  static Future<String> getSyncDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keySyncDeviceId);
    if (existing != null && existing.length >= 16) return existing;
    final generated = const Uuid().v4();
    await prefs.setString(_keySyncDeviceId, generated);
    return generated;
  }

  static Future<void> clearSyncCursors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSyncTime);
    await prefs.remove(_keyLastPushTime);
  }
}
