import 'dart:math';

import 'taste/dna_prefs.dart';
import 'taste/genre_weights.dart';
import 'taste/reco_signals.dart';

/// Zevk sinyalleri: tür ağırlıkları, benzerlik, öneri telemetrisi/gösterim
/// hafızası, dismiss geri bildirimi ve DNA cache + eşikleri.
///
/// İnce cephe: gerçek iş [PrefsGenreWeights], [PrefsRecoSignals] ve
/// [PrefsDnaPrefs] arasında bölünmüştür; call-site'lar taşınmasın diye burada
/// method-forwarder olarak tutulur.
///
/// Cycle kuralı: bu dosya `prefs_service.dart` import ETMEZ.
class PrefsTastePrefs {
  // ─── Tür ağırlıkları ────────────────────────────────────────────────────────

  static void invalidateGenreWeights() =>
      PrefsGenreWeights.invalidateGenreWeights();

  static Future<void> resetOnboarding() => PrefsGenreWeights.resetOnboarding();

  static Future<void> saveInitialGenres(List<int> genreIds) =>
      PrefsGenreWeights.saveInitialGenres(genreIds);

  static Future<Map<int, double>> getGenreWeights() =>
      PrefsGenreWeights.getGenreWeights();

  static double calculateSimilarity(
    Map<int, double> userVector,
    List<int> movieGenres,
  ) => PrefsGenreWeights.calculateSimilarity(userVector, movieGenres);

  static Future<List<int>> getLikedGenreIds() =>
      PrefsGenreWeights.getLikedGenreIds();

  static Future<List<int>> sampleLikedGenreIds(Random rng, {int count = 3}) =>
      PrefsGenreWeights.sampleLikedGenreIds(rng, count: count);

  // ─── Öneri isabet telemetrisi ────────────────────────────────────────────────

  static Future<void> recordRecoShown(Iterable<String?> sources) =>
      PrefsRecoSignals.recordRecoShown(sources);

  static Future<void> recordRecoLiked(String? source) =>
      PrefsRecoSignals.recordRecoLiked(source);

  static Future<void> revertRecoLiked(String? source) =>
      PrefsRecoSignals.revertRecoLiked(source);

  static Future<Map<String, Map<String, int>>> getRecoTelemetry() =>
      PrefsRecoSignals.getRecoTelemetry();

  static Future<bool> shouldAskDismissFeedback({required int matchScore}) =>
      PrefsRecoSignals.shouldAskDismissFeedback(matchScore: matchScore);

  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) => PrefsRecoSignals.recordDismissFeedback(
    movieKey: movieKey,
    reason: reason,
    source: source,
  );

  static Future<List<Map<String, dynamic>>> getDismissFeedback() =>
      PrefsRecoSignals.getDismissFeedback();

  // ─── Öneri gösterim hafızası (impression cooldown) ─────────────────────────

  static Future<Map<String, int>> getRecoImpressions() =>
      PrefsRecoSignals.getRecoImpressions();

  static Future<void> recordRecoImpressions(List<String> keys) =>
      PrefsRecoSignals.recordRecoImpressions(keys);

  static Future<Map<String, int>> getTonightHistory() =>
      PrefsRecoSignals.getTonightHistory();

  static Future<void> recordTonightPick(String key) =>
      PrefsRecoSignals.recordTonightPick(key);

  // ─── DNA Caching ─────────────────────────────────────────────────────────────

  static Future<Map<String, String>?> getCachedDna() =>
      PrefsDnaPrefs.getCachedDna();

  static Future<void> cacheDna(String json, String hash) =>
      PrefsDnaPrefs.cacheDna(json, hash);

  static Future<String?> getLastPublishedDnaHash() =>
      PrefsDnaPrefs.getLastPublishedDnaHash();

  static Future<void> setLastPublishedDnaHash(String? hash) =>
      PrefsDnaPrefs.setLastPublishedDnaHash(hash);

  static Future<void> clearDnaCache() => PrefsDnaPrefs.clearDnaCache();

  // ─── DNA eşik anları (swipe akışındaki keşif kartı) ─────────────────────

  static const dnaMilestones = PrefsDnaPrefs.dnaMilestones;

  static Future<int?> pendingDnaMilestone(int ratingCount) =>
      PrefsDnaPrefs.pendingDnaMilestone(ratingCount);

  static Future<void> markDnaMilestoneShown(int threshold) =>
      PrefsDnaPrefs.markDnaMilestoneShown(threshold);

  // ─── Bellek içi cache sıfırlama ─────────────────────────────────────────────

  static void resetInMemoryCaches() {
    PrefsRecoSignals.resetInMemoryCaches();
    PrefsGenreWeights.invalidateGenreWeights();
  }
}
