import 'package:flutter/foundation.dart';

import '../../models/movie.dart';
import '../cultural_preference_service.dart';
import '../db_helper.dart';
import 'favorite_weights.dart' as favorite_weights;
import 'taste_prefs.dart';

/// Kütüphane verisi: favoriler, puanlar, izleme listesi, arama geçmişi ve
/// sezon takibi. `DatabaseHelper` üzerindeki ince delege katmanı.
///
/// Public çağrı yüzeyi hâlâ [PrefsService]; bu sınıf taşıma hedefidir.
class PrefsLibraryFacade {
  // ─── Favourite movies / shows ────────────────────────────────────────────

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
    PrefsTastePrefs.invalidateGenreWeights();
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
    PrefsTastePrefs.invalidateGenreWeights();
  }

  /// Yeni seçimleri mevcut favorilerin ÜSTÜNE YAZMADAN birleştirir: var olan
  /// sıra korunur, listede olmayan yeni öğeler sona eklenir (20 sınırı). Onboarding
  /// buradan geçer — böylece "Zevk Analizini Yeniden Başlat" kullanıcının Top 20'sini
  /// 3'e düşürmez (bkz. TOP20_PLANI.md, Faz 1 clobber düzeltmesi).
  static const favoritesCap = favorite_weights.favoritesCap;

  /// Favori türlerin tür-ağırlığı formülünde [favoriteRankWeight] ile çarpılan
  /// taban katsayı.
  static const favoriteGenreBase = favorite_weights.favoriteGenreBase;

  /// Favorinin 0-tabanlı sırasını [0.2, 1.0] ağırlık çarpanına eşler: #1 (rank 0)
  /// = 1.0, son sıra (cap-1) ≈ 0.2. Öneri motorunun sıra eğrisinin tek kaynağı —
  /// hem tür ağırlığı hem keyword vektörü bunu kullanır (bkz. RecommendationEngine).
  static double favoriteRankWeight(int rank) =>
      favorite_weights.favoriteRankWeight(rank);

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
    PrefsTastePrefs.invalidateGenreWeights();
  }

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
    PrefsTastePrefs.invalidateGenreWeights();
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

  static Future<Set<String>> getRatedIds() async {
    return await DatabaseHelper().getRatedIds();
  }

  static Future<void> deleteRating(int movieId, bool isTV) async {
    await DatabaseHelper().deleteRating(movieId, isTV);
    PrefsTastePrefs.invalidateGenreWeights();
  }

  static Future<int> getRatingCount() async {
    return await DatabaseHelper().getRatingCount();
  }

  static Future<int> getFavoriteCount() async {
    return await DatabaseHelper().getFavoriteCount();
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
      final allGenres = await PrefsTastePrefs.getLikedGenreIds();
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

  static Future<int> getWatchlistCount() async {
    return await DatabaseHelper().getWatchlistCount();
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

  /// UI niyetini mutlak yazar (flip değil) — stale sheet LWW tersine çevirmesin.
  static Future<void> setSeasonWatched(
    int tvId,
    int seasonNumber,
    bool watched,
  ) async {
    await DatabaseHelper().toggleSeason(
      tvId,
      seasonNumber,
      deleted: watched ? 0 : 1,
    );
  }

  static Future<Set<int>> getWatchedSeasons(int tvId) async {
    return await DatabaseHelper().getWatchedSeasons(tvId);
  }
}
