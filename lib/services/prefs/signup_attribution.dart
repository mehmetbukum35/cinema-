import 'package:shared_preferences/shared_preferences.dart';

/// Hangi davet yüzeyinin kaydı ürettiğini taşır.
///
/// Dokunuş ile kayıt arasında bir giriş ekranı, muhtemelen bir e-posta
/// doğrulaması ve uygulamanın yeniden açılması olabilir; bu yüzden atıf
/// bellekte değil diskte bekler.
class PrefsSignupAttribution {
  static const _key = 'pending_signup_source';

  /// Davete dokunuldu. Kayıt gerçekleşene kadar saklanır.
  static Future<void> remember(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, source);
  }

  /// Bir kez okunur ve silinir: aynı atıf ikinci bir oturum açılışında
  /// tekrar gönderilirse ölçüm kaydı şişer.
  static Future<String?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_key);
    if (source != null) await prefs.remove(_key);
    return source;
  }
}
