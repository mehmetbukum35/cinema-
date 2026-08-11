import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db_helper.dart';

/// Uygulama ayarları (dil, tema, onboarding, blok listesi, UI bayrakları).
///
/// Public çağrı yüzeyi hâlâ [PrefsService]; bu sınıf taşıma hedefidir.
class PrefsAppSettings {
  static const _keyLanguage = 'selected_language';
  static const _keyOnboardingDone = 'onboarding_complete';
  static const _keyInitialGenres = 'initial_genres';
  static const _keyThemeMode = 'theme_mode'; // 'dark' | 'light' | 'system'
  static const _keyFamilyMode = 'family_mode';
  static const _keyBlockedMovies = 'blocked_movie_ids';

  static const _genreNames = {
    28: 'Aksiyon',
    12: 'Macera',
    16: 'Animasyon',
    35: 'Komedi',
    80: 'Suç',
    99: 'Belgesel',
    18: 'Drama',
    10751: 'Aile',
    14: 'Fantastik',
    36: 'Tarih',
    27: 'Korku',
    10402: 'Müzik',
    9648: 'Gizem',
    10749: 'Romantik',
    878: 'Bilim Kurgu',
    53: 'Gerilim',
    10752: 'Savaş',
    37: 'Western',
    10759: 'Aksiyon & Macera',
    10762: 'Çocuk',
    10763: 'Haber',
    10764: 'Reality',
    10765: 'Bilim Kurgu & Fantastik',
    10766: 'Pembe Dizi',
    10767: 'Talk Show',
    10768: 'Savaş & Siyaset',
  };

  static const _genreNamesEn = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Science Fiction',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
    10759: 'Action & Adventure',
    10762: 'Kids',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi & Fantasy',
    10766: 'Soap',
    10767: 'Talk Show',
    10768: 'War & Politics',
  };

  static String genreName(int id, {required String locale}) {
    if (locale == 'tr') {
      return _genreNames[id] ?? 'Bilinmeyen';
    } else {
      return _genreNamesEn[id] ?? 'Unknown';
    }
  }

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

  static Future<bool> isFamilyMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFamilyMode) ?? false;
  }

  static Future<void> setFamilyMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFamilyMode, value);
  }

  static Future<void> blockMovie(int id, bool isTV) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBlockedMovies) ?? [];
    final key = "${isTV ? 'tv' : 'movie'}_$id";
    if (!list.contains(key)) {
      list.add(key);
      await prefs.setStringList(_keyBlockedMovies, list);
    }
  }

  static Future<bool> isMovieBlocked(int id, bool isTV) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBlockedMovies) ?? [];
    final key = "${isTV ? 'tv' : 'movie'}_$id";
    return list.contains(key);
  }

  /// Engellenen yapımların anahtar seti — öneri motorunun kullandığı
  /// "movie_123"/"tv_456" biçimiyle birebir aynıdır; doğrudan excludedKeys'e
  /// karıştırılabilir. (Engellemeler daha önce yalnızca oturum içi listeden
  /// düşülüyordu; yeniden yüklemede geri gelebiliyordu.)
  static Future<Set<String>> getBlockedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyBlockedMovies) ?? []).toSet();
  }

  // ─── Theme mode ─────────────────────────────────────────────────────────────
  // Varsayılan 'light' — kayıt yoksa uygulama açık temayla açılır.

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'light';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  // ─── Onboarding ─────────────────────────────────────────────────────────────

  static const _keyOnboardingSkipTime = 'onboarding_skip_time';

  static Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_keyOnboardingDone) ?? false;

    if (done) {
      final skipTime = prefs.getInt(_keyOnboardingSkipTime);
      if (skipTime != null) {
        final skipDate = DateTime.fromMillisecondsSinceEpoch(skipTime);
        final difference = DateTime.now().difference(skipDate).inDays;

        // Eğer onboarding atlama üzerinden 3 gün geçmişse ve kullanıcının hiç değerlendirmesi yoksa, onboarding'i tekrar aktif et
        if (difference >= 3) {
          final count = await DatabaseHelper().getRatingCount();
          if (count == 0) {
            await prefs.setBool(_keyOnboardingDone, false);
            await prefs.remove(_keyOnboardingSkipTime);
            return false;
          }
        }
      }
    }
    return done;
  }

  static Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, true);
    await prefs.remove(
      _keyOnboardingSkipTime,
    ); // Anketi tamamen çözenlerin skip damgasını temizle
  }

  static Future<void> skipOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, true);
    await prefs.setInt(
      _keyOnboardingSkipTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static const _keyOnboardingBannerDismissed = 'onboarding_banner_dismissed';

  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, false);
    await prefs.remove(_keyOnboardingSkipTime);
    await prefs.remove(_keyInitialGenres);
    await prefs.remove(_keyInitialGenresSavedAt);
    await prefs.remove(_keyOnboardingBannerDismissed);
  }

  static Future<bool> isOnboardingBannerDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingBannerDismissed) ?? false;
  }

  static Future<void> dismissOnboardingBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingBannerDismissed, true);
  }

  // ─── Initial genre preferences ──────────────────────────────────────────────

  static const _keyInitialGenresSavedAt = 'initial_genres_saved_at';

  static Future<void> saveInitialGenres(List<int> genreIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInitialGenres, jsonEncode(genreIds));
    // Anket ağırlığının yavaş decay'i için referans anı (bkz. getGenreWeights).
    await prefs.setInt(
      _keyInitialGenresSavedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<List<int>> getInitialGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInitialGenres) ?? '[]';
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map((e) => e is num ? e.toInt() : (int.tryParse(e.toString()) ?? 0))
        .where((e) => e > 0)
        .toList();
  }

  /// Anket ağırlığının decay referans anı (ms). `PrefsTastePrefs` tür ağırlığı
  /// hesabında kullanır; bu anahtar `saveInitialGenres` ile birlikte yazılır.
  static Future<int?> getInitialGenresSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyInitialGenresSavedAt);
  }

  /// Eski kurulumlar için referans anı yoksa bir kereliğine damgalar.
  static Future<void> setInitialGenresSavedAt(
    int millisecondsSinceEpoch,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInitialGenresSavedAt, millisecondsSinceEpoch);
  }

  static Future<bool> isSwipeGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('swipe_guide_shown') ?? false;
  }

  static Future<void> setSwipeGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('swipe_guide_shown', true);
  }

  static Future<bool> isFirstTimeDice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('first_time_dice') ?? true;
  }

  static Future<void> setFirstTimeDiceSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_time_dice', false);
  }
}
