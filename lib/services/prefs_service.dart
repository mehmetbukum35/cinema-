import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/movie.dart';
import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/app_settings.dart';
import 'prefs/auth_storage.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';

class PrefsService {
  static String genreName(int id, {required String locale}) =>
      PrefsAppSettings.genreName(id, locale: locale);

  static Future<String?> getSelectedLanguage() =>
      PrefsAppSettings.getSelectedLanguage();

  static Future<void> setSelectedLanguage(String lang) =>
      PrefsAppSettings.setSelectedLanguage(lang);

  static Future<bool> isFamilyMode() => PrefsAppSettings.isFamilyMode();

  static Future<void> setFamilyMode(bool value) =>
      PrefsAppSettings.setFamilyMode(value);

  static Future<void> blockMovie(int id, bool isTV) =>
      PrefsAppSettings.blockMovie(id, isTV);

  static Future<bool> isMovieBlocked(int id, bool isTV) =>
      PrefsAppSettings.isMovieBlocked(id, isTV);

  static Future<Set<String>> getBlockedKeys() =>
      PrefsAppSettings.getBlockedKeys();

  static Future<String> getThemeMode() => PrefsAppSettings.getThemeMode();

  static Future<void> setThemeMode(String mode) =>
      PrefsAppSettings.setThemeMode(mode);

  static Future<bool> isOnboardingDone() => PrefsAppSettings.isOnboardingDone();

  static Future<void> setOnboardingDone() =>
      PrefsAppSettings.setOnboardingDone();

  static Future<void> skipOnboarding() => PrefsAppSettings.skipOnboarding();

  static Future<void> resetOnboarding() =>
      PrefsAppSettings.resetOnboarding().then((_) => invalidateGenreWeights());

  static Future<bool> isOnboardingBannerDismissed() =>
      PrefsAppSettings.isOnboardingBannerDismissed();

  static Future<void> dismissOnboardingBanner() =>
      PrefsAppSettings.dismissOnboardingBanner();

  static Future<void> saveInitialGenres(List<int> genreIds) =>
      PrefsAppSettings.saveInitialGenres(
        genreIds,
      ).then((_) => invalidateGenreWeights());

  static Future<List<int>> getInitialGenres() =>
      PrefsAppSettings.getInitialGenres();

  // ─── Favourite movies / shows ────────────────────────────────────────────────

  static Future<List<Movie>> getFavoriteMovies() =>
      DatabaseHelper().getFavorites(false);

  static Future<List<Movie>> getFavoriteTvShows() =>
      DatabaseHelper().getFavorites(true);

  /// Favori listesinin tamamını (sıra dahil) yeniden yazar. Top 20 düzenleme
  /// ekranı ve sıralama işlemleri buradan geçer — liste otoritedir.
  static Future<void> saveFavoriteMovies(
    List<Movie> movies, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().saveFavorites(
      movies,
      false,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
  }

  static Future<void> saveFavoriteTvShows(
    List<Movie> shows, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().saveFavorites(
      shows,
      true,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
  }

  /// Yeni seçimleri mevcut favorilerin ÜSTÜNE YAZMADAN birleştirir: var olan
  /// sıra korunur, listede olmayan yeni öğeler sona eklenir (20 sınırı). Onboarding
  /// buradan geçer — böylece "Zevk Analizini Yeniden Başlat" kullanıcının Top 20'sini
  /// 3'e düşürmez (bkz. TOP20_PLANI.md, Faz 1 clobber düzeltmesi).
  static const favoritesCap = 20;

  /// Favorinin 0-tabanlı sırasını [0.2, 1.0] ağırlık çarpanına eşler: #1 (rank 0)
  /// = 1.0, son sıra (cap-1) ≈ 0.2. Öneri motorunun sıra eğrisinin tek kaynağı —
  /// hem tür ağırlığı hem keyword vektörü bunu kullanır (bkz. RecommendationEngine).
  static double favoriteRankWeight(int rank) {
    final r = rank.clamp(0, favoritesCap - 1);
    return 1.0 - 0.8 * (r / (favoritesCap - 1));
  }

  static Future<void> mergeFavoriteMovies(
    List<Movie> picks, {
    required String metadataLocale,
  }) => _mergeFavorites(picks, false, metadataLocale);

  static Future<void> mergeFavoriteTvShows(
    List<Movie> picks, {
    required String metadataLocale,
  }) => _mergeFavorites(picks, true, metadataLocale);

  static Future<void> _mergeFavorites(
    List<Movie> picks,
    bool isTV,
    String metadataLocale,
  ) async {
    final existing = await DatabaseHelper().getFavorites(isTV);
    final merged = <Movie>[...existing];
    for (final pick in picks) {
      if (merged.length >= favoritesCap) break;
      if (merged.any((m) => m.id == pick.id)) continue;
      merged.add(pick);
    }
    // Değişiklik yoksa gereksiz yazma/sıra bozulması olmasın.
    if (merged.length == existing.length) return;
    await DatabaseHelper().saveFavorites(
      merged,
      isTV,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
  }

  // ─── Öneri isabet telemetrisi ────────────────────────────────────────────────

  static Future<void> recordRecoOutcome({
    required String source,
    required bool liked,
  }) => PrefsTastePrefs.recordRecoOutcome(source: source, liked: liked);

  static Future<void> revertRecoOutcome({
    required String source,
    required bool liked,
  }) => PrefsTastePrefs.revertRecoOutcome(source: source, liked: liked);

  /// Kaynak → {shown, liked} sayaçları. Beğeni oranı = liked/shown.
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() =>
      PrefsTastePrefs.getRecoTelemetry();

  static Future<bool> shouldAskDismissFeedback({required int matchScore}) =>
      PrefsTastePrefs.shouldAskDismissFeedback(matchScore: matchScore);

  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) => PrefsTastePrefs.recordDismissFeedback(
    movieKey: movieKey,
    reason: reason,
    source: source,
  );

  static Future<List<Map<String, dynamic>>> getDismissFeedback() =>
      PrefsTastePrefs.getDismissFeedback();

  // ─── Ratings ────────────────────────────────────────────────────────────────

  static Future<void> saveRating({
    Movie? movie,
    int? movieId,
    bool? isTV,
    required int rating,
    List<int>? genreIds,
    Object? comment = DatabaseHelper.unset,
    Object? isSpoiler = DatabaseHelper.unset,
    Object? isPrivate = DatabaseHelper.unset,
    required String metadataLocale,
  }) async {
    await DatabaseHelper().saveRating(
      movie: movie,
      movieId: movieId,
      isTV: isTV,
      rating: rating,
      genreIds: genreIds,
      comment: comment,
      isSpoiler: isSpoiler,
      isPrivate: isPrivate,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
    // Best-effort: yeterli sınıflandırılmış beğeni birikince kültürel tercihleri
    // yumuşak güncelle. Hata öneri akışını bozmasın.
    try {
      await CulturalPreferenceService.learnFromRatings();
    } catch (e) {
      debugPrint('Cultural preference learning failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) async {
    return DatabaseHelper().getRating(movieId, isTV);
  }

  /// Yorumu puandan bağımsız siler (puan korunur, sync'e yansır).
  static Future<void> deleteComment(int movieId, bool isTV) async {
    await DatabaseHelper().deleteComment(movieId, isTV);
  }

  /// Yorum yazılmış tüm puanlar, en yeni önce ("Yorumlarım" ekranı).
  static Future<List<Map<String, dynamic>>> getCommentedRatings() async {
    return DatabaseHelper().getCommentedRatings();
  }

  static Future<List<int>> getLikedGenreIds() =>
      PrefsTastePrefs.getLikedGenreIds();

  /// Tür ağırlık dağılımından, ağırlıkla orantılı olasılıkla [count] FARKLI
  /// tür örnekler (yerine koymadan). Hep aynı "top-3 tür" sorgusu yerine
  /// güne/tura bağlı bir [rng] ile çağrılırsa keşif havuzu çeşitlenir:
  /// 4-5. sıradaki türler de ara sıra vitrine aday üretir. Pozitif ağırlıklı
  /// tür sayısı yetersizse klasik getLikedGenreIds'e düşer.
  static Future<List<int>> sampleLikedGenreIds(Random rng, {int count = 3}) =>
      PrefsTastePrefs.sampleLikedGenreIds(rng, count: count);

  // ─── Öneri gösterim hafızası (impression cooldown) ─────────────────────────

  /// key → son gösterim (ms). 14 gün pencere, en fazla 400 kayıt.
  static Future<Map<String, int>> getRecoImpressions() =>
      PrefsTastePrefs.getRecoImpressions();

  static Future<void> recordRecoImpressions(List<String> keys) =>
      PrefsTastePrefs.recordRecoImpressions(keys);

  /// Vitrin ("Bu Gece Ne İzlesem?") geçmişi: aynı yapım 7 gün içinde tekrar
  /// vitrin olmasın diye ayrı ve daha uzun pencereli tutulur.
  static Future<Map<String, int>> getTonightHistory() =>
      PrefsTastePrefs.getTonightHistory();

  static Future<void> recordTonightPick(String key) =>
      PrefsTastePrefs.recordTonightPick(key);

  static void invalidateGenreWeights() =>
      PrefsTastePrefs.invalidateGenreWeights();

  static Future<Map<int, double>> getGenreWeights() =>
      PrefsTastePrefs.getGenreWeights();

  static double calculateSimilarity(
    Map<int, double> userVector,
    List<int> movieGenres,
  ) => PrefsTastePrefs.calculateSimilarity(userVector, movieGenres);

  static Future<Set<String>> getRatedIds() async {
    return await DatabaseHelper().getRatedIds();
  }

  static Future<void> deleteRating(int movieId, bool isTV) async {
    await DatabaseHelper().deleteRating(movieId, isTV);
    invalidateGenreWeights();
  }

  static Future<int> getRatingCount() async {
    return await DatabaseHelper().getRatingCount();
  }

  static Future<Map<String, dynamic>> getStats() async {
    final ratings = await DatabaseHelper().getRatings();

    final counts = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
    final Map<int, int> genreCounts = {};
    final List<Map<String, dynamic>> ratedMovies = [];

    for (final item in ratings) {
      final rating = item['rating'] as int;
      if (rating >= 0) {
        counts[rating] = (counts[rating] ?? 0) + 1;
        if (rating >= 2) {
          final genreList = item['genreIds'] as List? ?? const [];
          for (final id in genreList) {
            if (id is int) {
              genreCounts[id] = (genreCounts[id] ?? 0) + 1;
            }
          }
        }
        final movie = item['movie'] as Movie?;
        if (movie != null && movie.title.isNotEmpty) {
          ratedMovies.add({
            'movie': movie,
            'rating': rating,
            'is_private': item['is_private'] as int? ?? 0,
          });
        }
      }
    }

    List<int> topGenres;
    if (genreCounts.isEmpty) {
      // Fall back to weighted genre scores (favourites > initial prefs)
      final allGenres = await getLikedGenreIds();
      topGenres = allGenres.take(3).toList();
    } else {
      topGenres =
          (genreCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(3)
              .map((e) => e.key)
              .toList();
    }

    return {
      'total': ratings.where((e) => (e['rating'] as int) >= 0).length,
      'berbat': counts[0]!,
      'eh': counts[1]!,
      'iyi': counts[2]!,
      'harika': counts[3]!,
      'topGenres': topGenres,
      'ratedMovies': ratedMovies.reversed.toList(),
    };
  }

  // ─── Watchlist ───────────────────────────────────────────────────────────────

  static Future<void> addToWatchlist(
    Movie movie, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().addToWatchlist(
      movie,
      metadataLocale: metadataLocale,
    );
  }

  static Future<void> removeFromWatchlist(int id, bool isTV) async {
    await DatabaseHelper().removeFromWatchlist(id, isTV);
  }

  static Future<bool> isInWatchlist(int id, bool isTV) async {
    return await DatabaseHelper().isInWatchlist(id, isTV);
  }

  static Future<List<Movie>> getWatchlist() async {
    return await DatabaseHelper().getWatchlist();
  }

  // ─── Search history ─────────────────────────────────────────────────────────

  static Future<void> addSearchHistory(String query) async {
    await DatabaseHelper().addSearchHistory(query);
  }

  static Future<List<String>> getSearchHistory() async {
    return await DatabaseHelper().getSearchHistory();
  }

  static Future<void> clearSearchHistory() async {
    await DatabaseHelper().clearSearchHistory();
  }

  // ─── Season tracking ────────────────────────────────────────────────────────

  static Future<void> toggleSeason(int tvId, int seasonNumber) async {
    await DatabaseHelper().toggleSeason(tvId, seasonNumber);
  }

  static Future<Set<int>> getWatchedSeasons(int tvId) async {
    return await DatabaseHelper().getWatchedSeasons(tvId);
  }

  // ─── Reset ──────────────────────────────────────────────────────────────────

  static const _secureStorage = FlutterSecureStorage();

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
    await _secureStorage.deleteAll();
    await DatabaseHelper().clearAllData();
  }

  // ─── Authentication & Sync ──────────────────────────────────────────────────

  static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) => PrefsAuthStorage.saveTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  static Future<String?> getRefreshToken() =>
      PrefsAuthStorage.getRefreshToken();

  static Future<int> getLastSyncTime() => PrefsSyncMeta.getLastSyncTime();

  static Future<void> setLastSyncTime(int time) =>
      PrefsSyncMeta.setLastSyncTime(time);

  static Future<int> getLastPushTime() => PrefsSyncMeta.getLastPushTime();

  static Future<void> setLastPushTime(int time) =>
      PrefsSyncMeta.setLastPushTime(time);

  static Future<String> getSyncDeviceId() => PrefsSyncMeta.getSyncDeviceId();

  static Future<Map<String, dynamic>?> getUserData() =>
      PrefsAuthStorage.getUserData();

  static Future<void> saveUserData(Map<String, dynamic> userData) =>
      PrefsAuthStorage.saveUserData(userData);

  static Future<String?> getLastAuthenticatedUserId() =>
      PrefsAuthStorage.getLastAuthenticatedUserId();

  static Future<void> setLastAuthenticatedUserId(String? userId) =>
      PrefsAuthStorage.setLastAuthenticatedUserId(userId);

  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors();
    await PrefsTastePrefs.clearDnaCache();
  }

  /// Hesaba özel yerel tercihler (kültür + DNA cache). Wipe / hesap değişiminde.
  static Future<void> clearAccountScopedPreferences() async {
    await CulturalPreferenceService.clear();
    await PrefsTastePrefs.clearDnaCache();
  }

  // ─── DNA Caching ─────────────────────────────────────────────────────────────

  static Future<Map<String, String>?> getCachedDna() =>
      PrefsTastePrefs.getCachedDna();

  static Future<void> cacheDna(String json, String hash) =>
      PrefsTastePrefs.cacheDna(json, hash);

  static Future<String?> getLastPublishedDnaHash() =>
      PrefsTastePrefs.getLastPublishedDnaHash();

  static Future<void> setLastPublishedDnaHash(String? hash) =>
      PrefsTastePrefs.setLastPublishedDnaHash(hash);

  static Future<void> clearDnaCache() => PrefsTastePrefs.clearDnaCache();

  // ─── DNA eşik anları (swipe akışındaki keşif kartı) ─────────────────────

  /// İlk eşik, DNA'nın kilidinin açıldığı 5 puanla (bkz. DnaLockedCard) aynı.
  static const dnaMilestones = PrefsTastePrefs.dnaMilestones;

  /// [ratingCount] için gösterilmemiş en YÜKSEK eşik; hepsi gösterildiyse
  /// veya sayı ilk eşiğin altındaysa null.
  static Future<int?> pendingDnaMilestone(int ratingCount) =>
      PrefsTastePrefs.pendingDnaMilestone(ratingCount);

  /// [threshold] ve altındaki TÜM eşikleri gösterildi sayar: 50'nin kartını
  /// gören kullanıcıya sonradan 5'inki gösterilmez.
  static Future<void> markDnaMilestoneShown(int threshold) =>
      PrefsTastePrefs.markDnaMilestoneShown(threshold);

  static Future<bool> isSwipeGuideShown() =>
      PrefsAppSettings.isSwipeGuideShown();

  static Future<void> setSwipeGuideShown() =>
      PrefsAppSettings.setSwipeGuideShown();

  static Future<bool> isFirstTimeDice() => PrefsAppSettings.isFirstTimeDice();
}
