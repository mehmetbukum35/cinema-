// dart format width=100

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';
import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/app_settings.dart';
import 'prefs/auth_storage.dart';
import 'prefs/library_facade.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';

class PrefsService {
  /// Prefer [PrefsAppSettings.genreName].
  @Deprecated('Use PrefsAppSettings.genreName instead')
  static String genreName(int id, {required String locale}) =>
      PrefsAppSettings.genreName(id, locale: locale);

  /// Prefer [PrefsAppSettings.getSelectedLanguage].
  @Deprecated('Use PrefsAppSettings.getSelectedLanguage instead')
  static Future<String?> getSelectedLanguage() => PrefsAppSettings.getSelectedLanguage();

  /// Prefer [PrefsAppSettings.setSelectedLanguage].
  @Deprecated('Use PrefsAppSettings.setSelectedLanguage instead')
  static Future<void> setSelectedLanguage(String lang) =>
      PrefsAppSettings.setSelectedLanguage(lang);

  /// Prefer [PrefsAppSettings.isFamilyMode].
  @Deprecated('Use PrefsAppSettings.isFamilyMode instead')
  static Future<bool> isFamilyMode() => PrefsAppSettings.isFamilyMode();

  /// Prefer [PrefsAppSettings.setFamilyMode].
  @Deprecated('Use PrefsAppSettings.setFamilyMode instead')
  static Future<void> setFamilyMode(bool value) => PrefsAppSettings.setFamilyMode(value);

  /// Prefer [PrefsAppSettings.blockMovie].
  @Deprecated('Use PrefsAppSettings.blockMovie instead')
  static Future<void> blockMovie(int id, bool isTV) => PrefsAppSettings.blockMovie(id, isTV);

  /// Prefer [PrefsAppSettings.isMovieBlocked].
  @Deprecated('Use PrefsAppSettings.isMovieBlocked instead')
  static Future<bool> isMovieBlocked(int id, bool isTV) =>
      PrefsAppSettings.isMovieBlocked(id, isTV);

  /// Prefer [PrefsAppSettings.getBlockedKeys].
  @Deprecated('Use PrefsAppSettings.getBlockedKeys instead')
  static Future<Set<String>> getBlockedKeys() => PrefsAppSettings.getBlockedKeys();

  /// Prefer [PrefsAppSettings.getThemeMode].
  @Deprecated('Use PrefsAppSettings.getThemeMode instead')
  static Future<String> getThemeMode() => PrefsAppSettings.getThemeMode();

  /// Prefer [PrefsAppSettings.setThemeMode].
  @Deprecated('Use PrefsAppSettings.setThemeMode instead')
  static Future<void> setThemeMode(String mode) => PrefsAppSettings.setThemeMode(mode);

  /// Prefer [PrefsAppSettings.isOnboardingDone].
  @Deprecated('Use PrefsAppSettings.isOnboardingDone instead')
  static Future<bool> isOnboardingDone() => PrefsAppSettings.isOnboardingDone();

  /// Prefer [PrefsAppSettings.setOnboardingDone].
  @Deprecated('Use PrefsAppSettings.setOnboardingDone instead')
  static Future<void> setOnboardingDone() => PrefsAppSettings.setOnboardingDone();

  /// Prefer [PrefsAppSettings.skipOnboarding].
  @Deprecated('Use PrefsAppSettings.skipOnboarding instead')
  static Future<void> skipOnboarding() => PrefsAppSettings.skipOnboarding();

  /// Prefer [PrefsTastePrefs.resetOnboarding].
  @Deprecated('Use PrefsTastePrefs.resetOnboarding instead')
  static Future<void> resetOnboarding() => PrefsTastePrefs.resetOnboarding();

  /// Prefer [PrefsAppSettings.isOnboardingBannerDismissed].
  @Deprecated('Use PrefsAppSettings.isOnboardingBannerDismissed instead')
  static Future<bool> isOnboardingBannerDismissed() =>
      PrefsAppSettings.isOnboardingBannerDismissed();

  /// Prefer [PrefsAppSettings.dismissOnboardingBanner].
  @Deprecated('Use PrefsAppSettings.dismissOnboardingBanner instead')
  static Future<void> dismissOnboardingBanner() => PrefsAppSettings.dismissOnboardingBanner();

  /// Prefer [PrefsTastePrefs.saveInitialGenres].
  @Deprecated('Use PrefsTastePrefs.saveInitialGenres instead')
  static Future<void> saveInitialGenres(List<int> genreIds) =>
      PrefsTastePrefs.saveInitialGenres(genreIds);

  /// Prefer [PrefsAppSettings.getInitialGenres].
  @Deprecated('Use PrefsAppSettings.getInitialGenres instead')
  static Future<List<int>> getInitialGenres() => PrefsAppSettings.getInitialGenres();

  /// Prefer [PrefsAppSettings.isSwipeGuideShown].
  @Deprecated('Use PrefsAppSettings.isSwipeGuideShown instead')
  static Future<bool> isSwipeGuideShown() => PrefsAppSettings.isSwipeGuideShown();

  /// Prefer [PrefsAppSettings.setSwipeGuideShown].
  @Deprecated('Use PrefsAppSettings.setSwipeGuideShown instead')
  static Future<void> setSwipeGuideShown() => PrefsAppSettings.setSwipeGuideShown();

  /// Prefer [PrefsAppSettings.isFirstTimeDice].
  @Deprecated('Use PrefsAppSettings.isFirstTimeDice instead')
  static Future<bool> isFirstTimeDice() => PrefsAppSettings.isFirstTimeDice();

  /// Prefer [PrefsAuthStorage.getAccessToken].
  @Deprecated('Use PrefsAuthStorage.getAccessToken instead')
  static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();

  /// Prefer [PrefsAuthStorage.saveTokens].
  @Deprecated('Use PrefsAuthStorage.saveTokens instead')
  static Future<void> saveTokens({required String accessToken, required String refreshToken}) =>
      PrefsAuthStorage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);

  /// Prefer [PrefsAuthStorage.getRefreshToken].
  @Deprecated('Use PrefsAuthStorage.getRefreshToken instead')
  static Future<String?> getRefreshToken() => PrefsAuthStorage.getRefreshToken();

  /// Prefer [PrefsAuthStorage.getUserData].
  @Deprecated('Use PrefsAuthStorage.getUserData instead')
  static Future<Map<String, dynamic>?> getUserData() => PrefsAuthStorage.getUserData();

  /// Prefer [PrefsAuthStorage.saveUserData].
  @Deprecated('Use PrefsAuthStorage.saveUserData instead')
  static Future<void> saveUserData(Map<String, dynamic> userData) =>
      PrefsAuthStorage.saveUserData(userData);

  /// Prefer [PrefsAuthStorage.getLastAuthenticatedUserId].
  @Deprecated('Use PrefsAuthStorage.getLastAuthenticatedUserId instead')
  static Future<String?> getLastAuthenticatedUserId() =>
      PrefsAuthStorage.getLastAuthenticatedUserId();

  /// Prefer [PrefsAuthStorage.setLastAuthenticatedUserId].
  @Deprecated('Use PrefsAuthStorage.setLastAuthenticatedUserId instead')
  static Future<void> setLastAuthenticatedUserId(String? userId) =>
      PrefsAuthStorage.setLastAuthenticatedUserId(userId);

  /// Prefer [PrefsSyncMeta.getLastSyncTime].
  @Deprecated('Use PrefsSyncMeta.getLastSyncTime instead')
  static Future<int> getLastSyncTime() => PrefsSyncMeta.getLastSyncTime();

  /// Prefer [PrefsSyncMeta.setLastSyncTime].
  @Deprecated('Use PrefsSyncMeta.setLastSyncTime instead')
  static Future<void> setLastSyncTime(int time) => PrefsSyncMeta.setLastSyncTime(time);

  /// Prefer [PrefsSyncMeta.getLastPushTime].
  @Deprecated('Use PrefsSyncMeta.getLastPushTime instead')
  static Future<int> getLastPushTime() => PrefsSyncMeta.getLastPushTime();

  /// Prefer [PrefsSyncMeta.setLastPushTime].
  @Deprecated('Use PrefsSyncMeta.setLastPushTime instead')
  static Future<void> setLastPushTime(int time) => PrefsSyncMeta.setLastPushTime(time);

  /// Prefer [PrefsSyncMeta.getSyncDeviceId].
  @Deprecated('Use PrefsSyncMeta.getSyncDeviceId instead')
  static Future<String> getSyncDeviceId() => PrefsSyncMeta.getSyncDeviceId();

  static Future<void> recordRecoOutcome({required String source, required bool liked}) =>
      PrefsTastePrefs.recordRecoOutcome(source: source, liked: liked);

  static Future<void> revertRecoOutcome({required String source, required bool liked}) =>
      PrefsTastePrefs.revertRecoOutcome(source: source, liked: liked);

  static Future<Map<String, Map<String, int>>> getRecoTelemetry() =>
      PrefsTastePrefs.getRecoTelemetry();

  static Future<bool> shouldAskDismissFeedback({required int matchScore}) =>
      PrefsTastePrefs.shouldAskDismissFeedback(matchScore: matchScore);

  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) => PrefsTastePrefs.recordDismissFeedback(movieKey: movieKey, reason: reason, source: source);

  static Future<List<Map<String, dynamic>>> getDismissFeedback() =>
      PrefsTastePrefs.getDismissFeedback();

  static Future<List<int>> getLikedGenreIds() => PrefsTastePrefs.getLikedGenreIds();

  static Future<List<int>> sampleLikedGenreIds(Random rng, {int count = 3}) =>
      PrefsTastePrefs.sampleLikedGenreIds(rng, count: count);

  static Future<Map<String, int>> getRecoImpressions() => PrefsTastePrefs.getRecoImpressions();

  static Future<void> recordRecoImpressions(List<String> keys) =>
      PrefsTastePrefs.recordRecoImpressions(keys);

  static Future<Map<String, int>> getTonightHistory() => PrefsTastePrefs.getTonightHistory();

  static Future<void> recordTonightPick(String key) => PrefsTastePrefs.recordTonightPick(key);

  static void invalidateGenreWeights() => PrefsTastePrefs.invalidateGenreWeights();

  static Future<Map<int, double>> getGenreWeights() => PrefsTastePrefs.getGenreWeights();

  static double calculateSimilarity(Map<int, double> userVector, List<int> movieGenres) =>
      PrefsTastePrefs.calculateSimilarity(userVector, movieGenres);

  static Future<Map<String, String>?> getCachedDna() => PrefsTastePrefs.getCachedDna();

  static Future<void> cacheDna(String json, String hash) => PrefsTastePrefs.cacheDna(json, hash);

  static Future<String?> getLastPublishedDnaHash() => PrefsTastePrefs.getLastPublishedDnaHash();

  static Future<void> setLastPublishedDnaHash(String? hash) =>
      PrefsTastePrefs.setLastPublishedDnaHash(hash);

  static Future<void> clearDnaCache() => PrefsTastePrefs.clearDnaCache();

  static const dnaMilestones = PrefsTastePrefs.dnaMilestones;

  static Future<int?> pendingDnaMilestone(int ratingCount) =>
      PrefsTastePrefs.pendingDnaMilestone(ratingCount);

  static Future<void> markDnaMilestoneShown(int threshold) =>
      PrefsTastePrefs.markDnaMilestoneShown(threshold);

  static Future<List<Movie>> getFavoriteMovies() => PrefsLibraryFacade.getFavoriteMovies();

  static Future<List<Movie>> getFavoriteTvShows() => PrefsLibraryFacade.getFavoriteTvShows();

  static Future<void> saveFavoriteMovies(List<Movie> movies, {required String metadataLocale}) =>
      PrefsLibraryFacade.saveFavoriteMovies(movies, metadataLocale: metadataLocale);

  static Future<void> saveFavoriteTvShows(List<Movie> shows, {required String metadataLocale}) =>
      PrefsLibraryFacade.saveFavoriteTvShows(shows, metadataLocale: metadataLocale);

  static const favoritesCap = PrefsLibraryFacade.favoritesCap;

  static double favoriteRankWeight(int rank) => PrefsLibraryFacade.favoriteRankWeight(rank);

  static Future<void> mergeFavoriteMovies(List<Movie> picks, {required String metadataLocale}) =>
      PrefsLibraryFacade.mergeFavoriteMovies(picks, metadataLocale: metadataLocale);

  static Future<void> mergeFavoriteTvShows(List<Movie> picks, {required String metadataLocale}) =>
      PrefsLibraryFacade.mergeFavoriteTvShows(picks, metadataLocale: metadataLocale);

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
  }) => PrefsLibraryFacade.saveRating(
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

  static Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) =>
      PrefsLibraryFacade.getRating(movieId, isTV);

  static Future<void> deleteComment(int movieId, bool isTV) =>
      PrefsLibraryFacade.deleteComment(movieId, isTV);

  static Future<List<Map<String, dynamic>>> getCommentedRatings() =>
      PrefsLibraryFacade.getCommentedRatings();

  static Future<Set<String>> getRatedIds() => PrefsLibraryFacade.getRatedIds();

  static Future<void> deleteRating(int movieId, bool isTV) =>
      PrefsLibraryFacade.deleteRating(movieId, isTV);

  static Future<int> getRatingCount() => PrefsLibraryFacade.getRatingCount();

  static Future<Map<String, dynamic>> getStats() => PrefsLibraryFacade.getStats();

  static Future<void> addToWatchlist(Movie movie, {required String metadataLocale}) =>
      PrefsLibraryFacade.addToWatchlist(movie, metadataLocale: metadataLocale);

  static Future<void> removeFromWatchlist(int id, bool isTV) =>
      PrefsLibraryFacade.removeFromWatchlist(id, isTV);

  static Future<bool> isInWatchlist(int id, bool isTV) =>
      PrefsLibraryFacade.isInWatchlist(id, isTV);

  static Future<List<Movie>> getWatchlist() => PrefsLibraryFacade.getWatchlist();

  static Future<void> addSearchHistory(String query) => PrefsLibraryFacade.addSearchHistory(query);

  static Future<List<String>> getSearchHistory() => PrefsLibraryFacade.getSearchHistory();

  static Future<void> clearSearchHistory() => PrefsLibraryFacade.clearSearchHistory();

  static Future<void> toggleSeason(int tvId, int seasonNumber) =>
      PrefsLibraryFacade.toggleSeason(tvId, seasonNumber);

  static Future<Set<int>> getWatchedSeasons(int tvId) => PrefsLibraryFacade.getWatchedSeasons(tvId);

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
