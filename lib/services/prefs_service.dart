import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/movie.dart';
import 'db_helper.dart';

class PrefsService {
  static const _keyOnboardingDone = 'onboarding_complete';
  static const _keyInitialGenres = 'initial_genres';
  static const _keyLanguage = 'selected_language';
  static const _keyThemeMode = 'theme_mode'; // 'dark' | 'light' | 'system'
  static const _keyFamilyMode = 'family_mode';
  static const _keyBlockedMovies = 'blocked_movie_ids';
  static String activeLanguageCode = 'tr';

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

  static String genreName(int id) {
    if (activeLanguageCode == 'tr') {
      return _genreNames[id] ?? 'Bilinmeyen';
    } else {
      return _genreNamesEn[id] ?? 'Unknown';
    }
  }

  static Future<String?> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLanguage);
  }

  static Future<void> setSelectedLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
    activeLanguageCode = lang;
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

  // ─── Initial genre preferences ───────────────────────────────────────────────

  static Future<void> saveInitialGenres(List<int> genreIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInitialGenres, jsonEncode(genreIds));
  }

  static Future<List<int>> getInitialGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInitialGenres) ?? '[]';
    return (jsonDecode(raw) as List<dynamic>).map((e) => e as int).toList();
  }

  // ─── Favourite movies / shows ────────────────────────────────────────────────

  static Future<void> saveFavoriteMovies(List<Movie> movies) async {
    await DatabaseHelper().saveFavorites(movies, false);
  }

  static Future<void> saveFavoriteTvShows(List<Movie> shows) async {
    await DatabaseHelper().saveFavorites(shows, true);
  }

  // ─── Öneri isabet telemetrisi ────────────────────────────────────────────────
  // Kaynak bazında (discover/seed/friend) kaç öneri gösterilip kaçının
  // İyi/Harika aldığını sayar. Motorun gerçek başarısını ölçmenin tek yolu:
  // "önerdik → beğendi mi?" dönüşümü. Yalnızca cihazda tutulur.

  static const _keyRecoTelemetry = 'reco_telemetry_v1';

  static Future<void> recordRecoOutcome({
    required String source,
    required bool liked,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, dynamic> bucket =
        (data[source] as Map<String, dynamic>?) ?? {'shown': 0, 'liked': 0};
    bucket['shown'] = (bucket['shown'] as int) + 1;
    if (liked) bucket['liked'] = (bucket['liked'] as int) + 1;
    data[source] = bucket;
    await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
  }

  /// Kaynak → {shown, liked} sayaçları. Beğeni oranı = liked/shown.
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    return data.map(
      (k, v) => MapEntry(
        k,
        (v as Map<String, dynamic>).map((k2, v2) => MapEntry(k2, v2 as int)),
      ),
    );
  }

  // ─── Ratings ────────────────────────────────────────────────────────────────

  static Future<void> saveRating({
    Movie? movie,
    int? movieId,
    bool? isTV,
    required int rating,
    List<int>? genreIds,
    String? comment,
    int? isSpoiler,
  }) async {
    await DatabaseHelper().saveRating(
      movie: movie,
      movieId: movieId,
      isTV: isTV,
      rating: rating,
      genreIds: genreIds,
      comment: comment,
      isSpoiler: isSpoiler,
    );
  }

  static Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) async {
    return DatabaseHelper().getRating(movieId, isTV);
  }

  static Future<List<int>> getLikedGenreIds() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, int> counts = {};

    // Initial genre selections: weight 1
    final initialRaw = prefs.getString(_keyInitialGenres) ?? '[]';
    for (final id in (jsonDecode(initialRaw) as List<dynamic>)) {
      counts[id as int] = (counts[id] ?? 0) + 1;
    }

    // Favourite movies/shows: weight 3 (strongest taste signal)
    final db = DatabaseHelper();
    final favMovies = await db.getFavorites(false);
    final favShows = await db.getFavorites(true);
    for (final movie in [...favMovies, ...favShows]) {
      for (final id in movie.genreIds) {
        counts[id] = (counts[id] ?? 0) + 3;
      }
    }

    // Rating-derived genres: weight 2
    final ratings = await db.getRatings();
    for (final item in ratings) {
      if ((item['rating'] as int) >= 2) {
        final genreList = item['genreIds'] as List? ?? const [];
        for (final id in genreList) {
          if (id is int) {
            counts[id] = (counts[id] ?? 0) + 2;
          }
        }
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => e.key).toList();
  }

  static Future<Map<int, double>> getGenreWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, double> weights = {};

    // 1. Onboarding tür tercihleri: +1.0 (zaman aşımı yok)
    final initialRaw = prefs.getString(_keyInitialGenres) ?? '[]';
    for (final id in (jsonDecode(initialRaw) as List<dynamic>)) {
      weights[id as int] = (weights[id] ?? 0.0) + 1.0;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final db = DatabaseHelper();

    // 2. Favori film ve diziler: +3.0 (tür başına) * time decay
    final favorites = await db.getFavoritesRaw();
    for (final fav in favorites) {
      final String genreIdsRaw = fav['genre_ids'] as String? ?? '[]';
      final List<dynamic> genreIds = jsonDecode(genreIdsRaw);
      final int createdAt = fav['created_at'] as int? ?? now;
      final daysElapsed = (now - createdAt) / (24 * 3600 * 1000);
      final decayFactor = exp(-0.00385 * daysElapsed);

      for (final id in genreIds) {
        if (id is int) {
          weights[id] = (weights[id] ?? 0.0) + (3.0 * decayFactor);
        }
      }
    }

    // 3. Puanlamalardan elde edilen türler (Negatif cezalandırma) * time decay
    final ratings = await db.getRatings();
    for (final item in ratings) {
      final rating = item['rating'] as int;
      final genreList = item['genreIds'] as List? ?? const [];
      final int createdAt = item['created_at'] as int? ?? now;
      final daysElapsed = (now - createdAt) / (24 * 3600 * 1000);
      final decayFactor = exp(-0.00385 * daysElapsed);

      // Ağırlık belirleme:
      // Harika (3) -> +2.0, İyi (2) -> +1.0, Eh (1) -> -1.0, Berbat (0) -> -2.0
      double rWeight = 0.0;
      if (rating == 3) {
        rWeight = 2.0;
      } else if (rating == 2) {
        rWeight = 1.0;
      } else if (rating == 1) {
        rWeight = -1.0;
      } else if (rating == 0) {
        rWeight = -2.0;
      }

      if (rWeight != 0.0) {
        for (final id in genreList) {
          if (id is int) {
            weights[id] = (weights[id] ?? 0.0) + (rWeight * decayFactor);
          }
        }
      }
    }

    return weights;
  }

  static double calculateSimilarity(
    Map<int, double> userVector,
    List<int> movieGenres,
  ) {
    if (userVector.isEmpty || movieGenres.isEmpty) return 0.0;

    // Kullanıcı vektörünün Euclidean Norm'u (payda için): ||U|| = sqrt(sum(w^2))
    double sumUserSq = 0.0;
    for (final w in userVector.values) {
      sumUserSq += w * w;
    }
    if (sumUserSq == 0.0) return 0.0; // Cold-start/sıfıra bölme koruması
    final double userNorm = sqrt(sumUserSq);

    // Film vektörünün Euclidean Norm'u: ||M|| = sqrt(genreCount) (filmde her türün ağırlığı 1'dir)
    final double movieNorm = sqrt(movieGenres.length);

    // Vektör Dot Product: U · M = sum(userVector[g]) for g in movieGenres
    double dotProduct = 0.0;
    for (final gid in movieGenres) {
      dotProduct += userVector[gid] ?? 0.0;
    }

    // Kosinüs Benzerliği: (U · M) / (||U|| * ||M||)
    return dotProduct / (userNorm * movieNorm);
  }

  static Future<Set<String>> getRatedIds() async {
    return await DatabaseHelper().getRatedIds();
  }

  static Future<void> deleteRating(int movieId, bool isTV) async {
    await DatabaseHelper().deleteRating(movieId, isTV);
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
          ratedMovies.add({'movie': movie, 'rating': rating});
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

  static Future<void> addToWatchlist(Movie movie) async {
    await DatabaseHelper().addToWatchlist(movie);
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

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.deleteAll();
    await DatabaseHelper().clearAllData();
  }

  // ─── Authentication & Sync ──────────────────────────────────────────────────
  static const _keyAccessToken = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyLastSyncTime = 'sync_last_time';
  static const _keyUserData = 'auth_user_data';

  static Future<String?> getAccessToken() async {
    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyAccessToken);
    if (token != null) return token;

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyAccessToken);
    if (token != null) {
      await _secureStorage.write(key: _keyAccessToken, value: token);
      await prefs.remove(_keyAccessToken);
    }
    return token;
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
  }

  static Future<String?> getRefreshToken() async {
    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyRefreshToken);
    if (token != null) return token;

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyRefreshToken);
    if (token != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: token);
      await prefs.remove(_keyRefreshToken);
    }
    return token;
  }

  static Future<int> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSyncTime) ?? 0;
  }

  static Future<void> setLastSyncTime(int time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncTime, time);
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUserData);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserData, jsonEncode(userData));
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
    await prefs.remove(_keyLastSyncTime);
  }

  static Future<int?> getMovieRating(int movieId, bool isTV) async {
    final ratings = await DatabaseHelper().getRatings();
    final match = ratings.firstWhere(
      (r) =>
          r['movie_id'] == movieId &&
          (r['is_tv'] == 1) == isTV &&
          r['deleted'] != 1,
      orElse: () => <String, dynamic>{},
    );
    return match.isNotEmpty ? match['rating'] as int : null;
  }

  static Future<bool> isSwipeGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('swipe_guide_shown') ?? false;
  }

  static Future<void> setSwipeGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('swipe_guide_shown', true);
  }
}
