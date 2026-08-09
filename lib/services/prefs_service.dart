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

  /// Prefer [PrefsTastePrefs.recordRecoOutcome].
  @Deprecated('Use PrefsTastePrefs.recordRecoOutcome instead')
  static Future<void> recordRecoOutcome({required String source, required bool liked}) =>
      PrefsTastePrefs.recordRecoOutcome(source: source, liked: liked);

  /// Prefer [PrefsTastePrefs.revertRecoOutcome].
  @Deprecated('Use PrefsTastePrefs.revertRecoOutcome instead')
  static Future<void> revertRecoOutcome({required String source, required bool liked}) =>
      PrefsTastePrefs.revertRecoOutcome(source: source, liked: liked);

  /// Prefer [PrefsTastePrefs.getRecoTelemetry].
  @Deprecated('Use PrefsTastePrefs.getRecoTelemetry instead')
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() =>
      PrefsTastePrefs.getRecoTelemetry();

  /// Prefer [PrefsTastePrefs.shouldAskDismissFeedback].
  @Deprecated('Use PrefsTastePrefs.shouldAskDismissFeedback instead')
  static Future<bool> shouldAskDismissFeedback({required int matchScore}) =>
      PrefsTastePrefs.shouldAskDismissFeedback(matchScore: matchScore);

  /// Prefer [PrefsTastePrefs.recordDismissFeedback].
  @Deprecated('Use PrefsTastePrefs.recordDismissFeedback instead')
  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) => PrefsTastePrefs.recordDismissFeedback(movieKey: movieKey, reason: reason, source: source);

  /// Prefer [PrefsTastePrefs.getDismissFeedback].
  @Deprecated('Use PrefsTastePrefs.getDismissFeedback instead')
  static Future<List<Map<String, dynamic>>> getDismissFeedback() =>
      PrefsTastePrefs.getDismissFeedback();

  /// Prefer [PrefsTastePrefs.getLikedGenreIds].
  @Deprecated('Use PrefsTastePrefs.getLikedGenreIds instead')
  static Future<List<int>> getLikedGenreIds() => PrefsTastePrefs.getLikedGenreIds();

  /// Prefer [PrefsTastePrefs.sampleLikedGenreIds].
  @Deprecated('Use PrefsTastePrefs.sampleLikedGenreIds instead')
  static Future<List<int>> sampleLikedGenreIds(Random rng, {int count = 3}) =>
      PrefsTastePrefs.sampleLikedGenreIds(rng, count: count);

  /// Prefer [PrefsTastePrefs.getRecoImpressions].
  @Deprecated('Use PrefsTastePrefs.getRecoImpressions instead')
  static Future<Map<String, int>> getRecoImpressions() => PrefsTastePrefs.getRecoImpressions();

  /// Prefer [PrefsTastePrefs.recordRecoImpressions].
  @Deprecated('Use PrefsTastePrefs.recordRecoImpressions instead')
  static Future<void> recordRecoImpressions(List<String> keys) =>
      PrefsTastePrefs.recordRecoImpressions(keys);

  /// Prefer [PrefsTastePrefs.getTonightHistory].
  @Deprecated('Use PrefsTastePrefs.getTonightHistory instead')
  static Future<Map<String, int>> getTonightHistory() => PrefsTastePrefs.getTonightHistory();

  /// Prefer [PrefsTastePrefs.recordTonightPick].
  @Deprecated('Use PrefsTastePrefs.recordTonightPick instead')
  static Future<void> recordTonightPick(String key) => PrefsTastePrefs.recordTonightPick(key);

  /// Prefer [PrefsTastePrefs.invalidateGenreWeights].
  @Deprecated('Use PrefsTastePrefs.invalidateGenreWeights instead')
  static void invalidateGenreWeights() => PrefsTastePrefs.invalidateGenreWeights();

  /// Prefer [PrefsTastePrefs.getGenreWeights].
  @Deprecated('Use PrefsTastePrefs.getGenreWeights instead')
  static Future<Map<int, double>> getGenreWeights() => PrefsTastePrefs.getGenreWeights();

  /// Prefer [PrefsTastePrefs.calculateSimilarity].
  @Deprecated('Use PrefsTastePrefs.calculateSimilarity instead')
  static double calculateSimilarity(Map<int, double> userVector, List<int> movieGenres) =>
      PrefsTastePrefs.calculateSimilarity(userVector, movieGenres);

  /// Prefer [PrefsTastePrefs.getCachedDna].
  @Deprecated('Use PrefsTastePrefs.getCachedDna instead')
  static Future<Map<String, String>?> getCachedDna() => PrefsTastePrefs.getCachedDna();

  /// Prefer [PrefsTastePrefs.cacheDna].
  @Deprecated('Use PrefsTastePrefs.cacheDna instead')
  static Future<void> cacheDna(String json, String hash) => PrefsTastePrefs.cacheDna(json, hash);

  /// Prefer [PrefsTastePrefs.getLastPublishedDnaHash].
  @Deprecated('Use PrefsTastePrefs.getLastPublishedDnaHash instead')
  static Future<String?> getLastPublishedDnaHash() => PrefsTastePrefs.getLastPublishedDnaHash();

  /// Prefer [PrefsTastePrefs.setLastPublishedDnaHash].
  @Deprecated('Use PrefsTastePrefs.setLastPublishedDnaHash instead')
  static Future<void> setLastPublishedDnaHash(String? hash) =>
      PrefsTastePrefs.setLastPublishedDnaHash(hash);

  /// Prefer [PrefsTastePrefs.clearDnaCache].
  @Deprecated('Use PrefsTastePrefs.clearDnaCache instead')
  static Future<void> clearDnaCache() => PrefsTastePrefs.clearDnaCache();

  /// Prefer [PrefsTastePrefs.dnaMilestones].
  @Deprecated('Use PrefsTastePrefs.dnaMilestones instead')
  static const dnaMilestones = PrefsTastePrefs.dnaMilestones;

  /// Prefer [PrefsTastePrefs.pendingDnaMilestone].
  @Deprecated('Use PrefsTastePrefs.pendingDnaMilestone instead')
  static Future<int?> pendingDnaMilestone(int ratingCount) =>
      PrefsTastePrefs.pendingDnaMilestone(ratingCount);

  /// Prefer [PrefsTastePrefs.markDnaMilestoneShown].
  @Deprecated('Use PrefsTastePrefs.markDnaMilestoneShown instead')
  static Future<void> markDnaMilestoneShown(int threshold) =>
      PrefsTastePrefs.markDnaMilestoneShown(threshold);

  /// Prefer [PrefsLibraryFacade.getFavoriteMovies].
  @Deprecated('Use PrefsLibraryFacade.getFavoriteMovies instead')
  static Future<List<Movie>> getFavoriteMovies() => PrefsLibraryFacade.getFavoriteMovies();

  /// Prefer [PrefsLibraryFacade.getFavoriteTvShows].
  @Deprecated('Use PrefsLibraryFacade.getFavoriteTvShows instead')
  static Future<List<Movie>> getFavoriteTvShows() => PrefsLibraryFacade.getFavoriteTvShows();

  /// Prefer [PrefsLibraryFacade.saveFavoriteMovies].
  @Deprecated('Use PrefsLibraryFacade.saveFavoriteMovies instead')
  static Future<void> saveFavoriteMovies(List<Movie> movies, {required String metadataLocale}) =>
      PrefsLibraryFacade.saveFavoriteMovies(movies, metadataLocale: metadataLocale);

  /// Prefer [PrefsLibraryFacade.saveFavoriteTvShows].
  @Deprecated('Use PrefsLibraryFacade.saveFavoriteTvShows instead')
  static Future<void> saveFavoriteTvShows(List<Movie> shows, {required String metadataLocale}) =>
      PrefsLibraryFacade.saveFavoriteTvShows(shows, metadataLocale: metadataLocale);

  /// Prefer [PrefsLibraryFacade.favoritesCap].
  @Deprecated('Use PrefsLibraryFacade.favoritesCap instead')
  static const favoritesCap = PrefsLibraryFacade.favoritesCap;

  /// Prefer [PrefsLibraryFacade.favoriteRankWeight].
  @Deprecated('Use PrefsLibraryFacade.favoriteRankWeight instead')
  static double favoriteRankWeight(int rank) => PrefsLibraryFacade.favoriteRankWeight(rank);

  /// Prefer [PrefsLibraryFacade.mergeFavoriteMovies].
  @Deprecated('Use PrefsLibraryFacade.mergeFavoriteMovies instead')
  static Future<void> mergeFavoriteMovies(List<Movie> picks, {required String metadataLocale}) =>
      PrefsLibraryFacade.mergeFavoriteMovies(picks, metadataLocale: metadataLocale);

  /// Prefer [PrefsLibraryFacade.mergeFavoriteTvShows].
  @Deprecated('Use PrefsLibraryFacade.mergeFavoriteTvShows instead')
  static Future<void> mergeFavoriteTvShows(List<Movie> picks, {required String metadataLocale}) =>
      PrefsLibraryFacade.mergeFavoriteTvShows(picks, metadataLocale: metadataLocale);

  /// Prefer [PrefsLibraryFacade.saveRating].
  @Deprecated('Use PrefsLibraryFacade.saveRating instead')
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

  /// Prefer [PrefsLibraryFacade.getRating].
  @Deprecated('Use PrefsLibraryFacade.getRating instead')
  static Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) =>
      PrefsLibraryFacade.getRating(movieId, isTV);

  /// Prefer [PrefsLibraryFacade.deleteComment].
  @Deprecated('Use PrefsLibraryFacade.deleteComment instead')
  static Future<void> deleteComment(int movieId, bool isTV) =>
      PrefsLibraryFacade.deleteComment(movieId, isTV);

  /// Prefer [PrefsLibraryFacade.getCommentedRatings].
  @Deprecated('Use PrefsLibraryFacade.getCommentedRatings instead')
  static Future<List<Map<String, dynamic>>> getCommentedRatings() =>
      PrefsLibraryFacade.getCommentedRatings();

  /// Prefer [PrefsLibraryFacade.getRatedIds].
  @Deprecated('Use PrefsLibraryFacade.getRatedIds instead')
  static Future<Set<String>> getRatedIds() => PrefsLibraryFacade.getRatedIds();

  /// Prefer [PrefsLibraryFacade.deleteRating].
  @Deprecated('Use PrefsLibraryFacade.deleteRating instead')
  static Future<void> deleteRating(int movieId, bool isTV) =>
      PrefsLibraryFacade.deleteRating(movieId, isTV);

  /// Prefer [PrefsLibraryFacade.getRatingCount].
  @Deprecated('Use PrefsLibraryFacade.getRatingCount instead')
  static Future<int> getRatingCount() => PrefsLibraryFacade.getRatingCount();

  /// Prefer [PrefsLibraryFacade.getStats].
  @Deprecated('Use PrefsLibraryFacade.getStats instead')
  static Future<Map<String, dynamic>> getStats() => PrefsLibraryFacade.getStats();

  /// Prefer [PrefsLibraryFacade.addToWatchlist].
  @Deprecated('Use PrefsLibraryFacade.addToWatchlist instead')
  static Future<void> addToWatchlist(Movie movie, {required String metadataLocale}) =>
      PrefsLibraryFacade.addToWatchlist(movie, metadataLocale: metadataLocale);

  /// Prefer [PrefsLibraryFacade.removeFromWatchlist].
  @Deprecated('Use PrefsLibraryFacade.removeFromWatchlist instead')
  static Future<void> removeFromWatchlist(int id, bool isTV) =>
      PrefsLibraryFacade.removeFromWatchlist(id, isTV);

  /// Prefer [PrefsLibraryFacade.isInWatchlist].
  @Deprecated('Use PrefsLibraryFacade.isInWatchlist instead')
  static Future<bool> isInWatchlist(int id, bool isTV) =>
      PrefsLibraryFacade.isInWatchlist(id, isTV);

  /// Prefer [PrefsLibraryFacade.getWatchlist].
  @Deprecated('Use PrefsLibraryFacade.getWatchlist instead')
  static Future<List<Movie>> getWatchlist() => PrefsLibraryFacade.getWatchlist();

  /// Prefer [PrefsLibraryFacade.addSearchHistory].
  @Deprecated('Use PrefsLibraryFacade.addSearchHistory instead')
  static Future<void> addSearchHistory(String query) => PrefsLibraryFacade.addSearchHistory(query);

  /// Prefer [PrefsLibraryFacade.getSearchHistory].
  @Deprecated('Use PrefsLibraryFacade.getSearchHistory instead')
  static Future<List<String>> getSearchHistory() => PrefsLibraryFacade.getSearchHistory();

  /// Prefer [PrefsLibraryFacade.clearSearchHistory].
  @Deprecated('Use PrefsLibraryFacade.clearSearchHistory instead')
  static Future<void> clearSearchHistory() => PrefsLibraryFacade.clearSearchHistory();

  /// Prefer [PrefsLibraryFacade.toggleSeason].
  @Deprecated('Use PrefsLibraryFacade.toggleSeason instead')
  static Future<void> toggleSeason(int tvId, int seasonNumber) =>
      PrefsLibraryFacade.toggleSeason(tvId, seasonNumber);

  /// Prefer [PrefsLibraryFacade.getWatchedSeasons].
  @Deprecated('Use PrefsLibraryFacade.getWatchedSeasons instead')
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
