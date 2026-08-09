// dart format width=100

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/app_settings.dart';
import 'prefs/auth_storage.dart';
import 'prefs/library_facade.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';

class PrefsService {
  static final genreName = PrefsAppSettings.genreName;
  static final getSelectedLanguage = PrefsAppSettings.getSelectedLanguage;
  static final setSelectedLanguage = PrefsAppSettings.setSelectedLanguage;
  static final isFamilyMode = PrefsAppSettings.isFamilyMode;
  static final setFamilyMode = PrefsAppSettings.setFamilyMode;
  static final blockMovie = PrefsAppSettings.blockMovie;
  static final isMovieBlocked = PrefsAppSettings.isMovieBlocked;
  static final getBlockedKeys = PrefsAppSettings.getBlockedKeys;
  static final getThemeMode = PrefsAppSettings.getThemeMode;
  static final setThemeMode = PrefsAppSettings.setThemeMode;
  static final isOnboardingDone = PrefsAppSettings.isOnboardingDone;
  static final setOnboardingDone = PrefsAppSettings.setOnboardingDone;
  static final skipOnboarding = PrefsAppSettings.skipOnboarding;
  static final resetOnboarding = PrefsTastePrefs.resetOnboarding;
  static final isOnboardingBannerDismissed = PrefsAppSettings.isOnboardingBannerDismissed;
  static final dismissOnboardingBanner = PrefsAppSettings.dismissOnboardingBanner;
  static final saveInitialGenres = PrefsTastePrefs.saveInitialGenres;
  static final getInitialGenres = PrefsAppSettings.getInitialGenres;
  static final isSwipeGuideShown = PrefsAppSettings.isSwipeGuideShown;
  static final setSwipeGuideShown = PrefsAppSettings.setSwipeGuideShown;
  static final isFirstTimeDice = PrefsAppSettings.isFirstTimeDice;
  static final getAccessToken = PrefsAuthStorage.getAccessToken;
  static final saveTokens = PrefsAuthStorage.saveTokens;
  static final getRefreshToken = PrefsAuthStorage.getRefreshToken;
  static final getUserData = PrefsAuthStorage.getUserData;
  static final saveUserData = PrefsAuthStorage.saveUserData;
  static final getLastAuthenticatedUserId = PrefsAuthStorage.getLastAuthenticatedUserId;
  static final setLastAuthenticatedUserId = PrefsAuthStorage.setLastAuthenticatedUserId;
  static final getLastSyncTime = PrefsSyncMeta.getLastSyncTime;
  static final setLastSyncTime = PrefsSyncMeta.setLastSyncTime;
  static final getLastPushTime = PrefsSyncMeta.getLastPushTime;
  static final setLastPushTime = PrefsSyncMeta.setLastPushTime;
  static final getSyncDeviceId = PrefsSyncMeta.getSyncDeviceId;
  static final recordRecoOutcome = PrefsTastePrefs.recordRecoOutcome;
  static final revertRecoOutcome = PrefsTastePrefs.revertRecoOutcome;
  static final getRecoTelemetry = PrefsTastePrefs.getRecoTelemetry;
  static final shouldAskDismissFeedback = PrefsTastePrefs.shouldAskDismissFeedback;
  static final recordDismissFeedback = PrefsTastePrefs.recordDismissFeedback;
  static final getDismissFeedback = PrefsTastePrefs.getDismissFeedback;
  static final getLikedGenreIds = PrefsTastePrefs.getLikedGenreIds;
  static final sampleLikedGenreIds = PrefsTastePrefs.sampleLikedGenreIds;
  static final getRecoImpressions = PrefsTastePrefs.getRecoImpressions;
  static final recordRecoImpressions = PrefsTastePrefs.recordRecoImpressions;
  static final getTonightHistory = PrefsTastePrefs.getTonightHistory;
  static final recordTonightPick = PrefsTastePrefs.recordTonightPick;
  static final invalidateGenreWeights = PrefsTastePrefs.invalidateGenreWeights;
  static final getGenreWeights = PrefsTastePrefs.getGenreWeights;
  static final calculateSimilarity = PrefsTastePrefs.calculateSimilarity;
  static final getCachedDna = PrefsTastePrefs.getCachedDna;
  static final cacheDna = PrefsTastePrefs.cacheDna;
  static final getLastPublishedDnaHash = PrefsTastePrefs.getLastPublishedDnaHash;
  static final setLastPublishedDnaHash = PrefsTastePrefs.setLastPublishedDnaHash;
  static final clearDnaCache = PrefsTastePrefs.clearDnaCache;
  static const dnaMilestones = PrefsTastePrefs.dnaMilestones;
  static final pendingDnaMilestone = PrefsTastePrefs.pendingDnaMilestone;
  static final markDnaMilestoneShown = PrefsTastePrefs.markDnaMilestoneShown;
  static final getFavoriteMovies = PrefsLibraryFacade.getFavoriteMovies;
  static final getFavoriteTvShows = PrefsLibraryFacade.getFavoriteTvShows;
  static final saveFavoriteMovies = PrefsLibraryFacade.saveFavoriteMovies;
  static final saveFavoriteTvShows = PrefsLibraryFacade.saveFavoriteTvShows;
  static const favoritesCap = PrefsLibraryFacade.favoritesCap;
  static final favoriteRankWeight = PrefsLibraryFacade.favoriteRankWeight;
  static final mergeFavoriteMovies = PrefsLibraryFacade.mergeFavoriteMovies;
  static final mergeFavoriteTvShows = PrefsLibraryFacade.mergeFavoriteTvShows;
  static final saveRating = PrefsLibraryFacade.saveRating;
  static final getRating = PrefsLibraryFacade.getRating;
  static final deleteComment = PrefsLibraryFacade.deleteComment;
  static final getCommentedRatings = PrefsLibraryFacade.getCommentedRatings;
  static final getRatedIds = PrefsLibraryFacade.getRatedIds;
  static final deleteRating = PrefsLibraryFacade.deleteRating;
  static final getRatingCount = PrefsLibraryFacade.getRatingCount;
  static final getStats = PrefsLibraryFacade.getStats;
  static final addToWatchlist = PrefsLibraryFacade.addToWatchlist;
  static final removeFromWatchlist = PrefsLibraryFacade.removeFromWatchlist;
  static final isInWatchlist = PrefsLibraryFacade.isInWatchlist;
  static final getWatchlist = PrefsLibraryFacade.getWatchlist;
  static final addSearchHistory = PrefsLibraryFacade.addSearchHistory;
  static final getSearchHistory = PrefsLibraryFacade.getSearchHistory;
  static final clearSearchHistory = PrefsLibraryFacade.clearSearchHistory;
  static final toggleSeason = PrefsLibraryFacade.toggleSeason;
  static final getWatchedSeasons = PrefsLibraryFacade.getWatchedSeasons;
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
