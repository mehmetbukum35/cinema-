import 'package:shared_preferences/shared_preferences.dart';

/// Zevk DNA'sı: hesaplanan DNA'nın cache'i (girdi hash'i ile birlikte),
/// sunucuya son yayınlanan hash ve swipe akışındaki keşif eşikleri.
///
/// Public çağrı yüzeyi hâlâ [PrefsTastePrefs]; bu sınıf taşıma hedefidir.
///
/// Cycle kuralı: bu dosya `prefs_service.dart` import ETMEZ.
class PrefsDnaPrefs {
  // ─── DNA Caching ─────────────────────────────────────────────────────────────
  static const _keyLastDnaJson = 'last_dna_json';
  static const _keyLastDnaInputHash = 'last_dna_input_hash';
  static const _keyLastPublishedDnaHash = 'last_published_dna_hash';

  static Future<Map<String, String>?> getCachedDna() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyLastDnaJson);
    final hash = prefs.getString(_keyLastDnaInputHash);
    if (json != null && hash != null) {
      return {'json': json, 'hash': hash};
    }
    return null;
  }

  static Future<void> cacheDna(String json, String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastDnaJson, json);
    await prefs.setString(_keyLastDnaInputHash, hash);
  }

  static Future<String?> getLastPublishedDnaHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastPublishedDnaHash);
  }

  static Future<void> setLastPublishedDnaHash(String? hash) async {
    final prefs = await SharedPreferences.getInstance();
    if (hash == null) {
      await prefs.remove(_keyLastPublishedDnaHash);
    } else {
      await prefs.setString(_keyLastPublishedDnaHash, hash);
    }
  }

  static Future<void> clearDnaCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastDnaJson);
    await prefs.remove(_keyLastDnaInputHash);
    await prefs.remove(_keyLastPublishedDnaHash);
  }

  // ─── DNA eşik anları (swipe akışındaki keşif kartı) ─────────────────────
  // DNA'nın tek girişi Profil sekmesindeki banner'dı; çekirdek döngüde (swipe)
  // yaşayan kullanıcı özelliğin varlığını hiç öğrenmiyordu. Bu eşikler,
  // puanlama sayısı büyürken DNA'yı bir kez davetle keşfettirir.

  /// İlk eşik, DNA'nın kilidinin açıldığı 5 puanla (bkz. DnaLockedCard) aynı.
  static const dnaMilestones = [5, 25, 50];
  static const _keyDnaMilestonesShown = 'dna_milestones_shown_v1';

  /// [ratingCount] için gösterilmemiş en YÜKSEK eşik; hepsi gösterildiyse
  /// veya sayı ilk eşiğin altındaysa null.
  static Future<int?> pendingDnaMilestone(int ratingCount) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getStringList(_keyDnaMilestonesShown) ?? const [];
    for (final t in dnaMilestones.reversed) {
      if (ratingCount >= t && !shown.contains('$t')) return t;
    }
    return null;
  }

  /// [threshold] ve altındaki TÜM eşikleri gösterildi sayar: 50'nin kartını
  /// gören kullanıcıya sonradan 5'inki gösterilmez.
  static Future<void> markDnaMilestoneShown(int threshold) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getStringList(_keyDnaMilestonesShown) ?? const [];
    final updated = <String>{
      ...shown,
      for (final t in dnaMilestones)
        if (t <= threshold) '$t',
    };
    await prefs.setStringList(_keyDnaMilestonesShown, updated.toList());
  }
}
