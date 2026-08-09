// dart format width=100

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/auth_storage.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';

class PrefsService {
  /// Bellekte tutulan performans cache'lerini sıfırlar. Diske dokunmaz.
  ///
  /// Testler için gerekli: bu cache'ler statik olduğundan bir testin yazdığı
  /// token veya tür ağırlığı aynı dosyadaki sonraki testlere sızar ve testleri
  /// çalışma sırasına bağımlı kılar.
  @visibleForTesting
  static void resetInMemoryCaches() {
    PrefsAuthStorage.clearTokenCache();
    PrefsTastePrefs.resetInMemoryCaches();
  }

  static Future<void> resetAll() async {
    resetInMemoryCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await PrefsAuthStorage.deleteAllSecure();
    await DatabaseHelper().clearAllData();
  }

  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors();
    await PrefsTastePrefs.clearDnaCache();
  }

  static Future<void> clearAccountScopedPreferences() async {
    await CulturalPreferenceService.clear();
    await PrefsTastePrefs.clearDnaCache();
  }
}
