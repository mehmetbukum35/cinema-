import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama ayarları (dil, tema, onboarding, blok listesi, UI bayrakları).
///
/// Public çağrı yüzeyi hâlâ [PrefsService]; bu sınıf taşıma hedefidir.
class PrefsAppSettings {
  static const _keyLanguage = 'selected_language';

  static Future<String?> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLanguage);
  }

  /// Yalnızca kalıcılaştırır. Aktif dilin sahibi `LocaleNotifier`'dır; buradan
  /// ikinci bir yazma yapılırsa iki kaynak ayrışır.
  static Future<void> setSelectedLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
  }
}
