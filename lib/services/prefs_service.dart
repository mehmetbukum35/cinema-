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
    invalidateGenreWeights();
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

  static const _keyInitialGenresSavedAt = 'initial_genres_saved_at';

  static Future<void> saveInitialGenres(List<int> genreIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInitialGenres, jsonEncode(genreIds));
    // Anket ağırlığının yavaş decay'i için referans anı (bkz. getGenreWeights).
    await prefs.setInt(
      _keyInitialGenresSavedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    invalidateGenreWeights();
  }

  static Future<List<int>> getInitialGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInitialGenres) ?? '[]';
    return (jsonDecode(raw) as List<dynamic>).map((e) => e as int).toList();
  }

  // ─── Favourite movies / shows ────────────────────────────────────────────────

  static Future<void> saveFavoriteMovies(List<Movie> movies) async {
    await DatabaseHelper().saveFavorites(
      movies,
      false,
      metadataLocale: activeLanguageCode,
    );
    invalidateGenreWeights();
  }

  static Future<void> saveFavoriteTvShows(List<Movie> shows) async {
    await DatabaseHelper().saveFavorites(
      shows,
      true,
      metadataLocale: activeLanguageCode,
    );
    invalidateGenreWeights();
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

  static Future<void> revertRecoOutcome({
    required String source,
    required bool liked,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, dynamic> bucket =
        (data[source] as Map<String, dynamic>?) ?? {'shown': 0, 'liked': 0};
    if ((bucket['shown'] as int) > 0) {
      bucket['shown'] = (bucket['shown'] as int) - 1;
    }
    if (liked && (bucket['liked'] as int) > 0) {
      bucket['liked'] = (bucket['liked'] as int) - 1;
    }
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
    Object? comment = DatabaseHelper.unset,
    Object? isSpoiler = DatabaseHelper.unset,
    Object? isPrivate = DatabaseHelper.unset,
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
      metadataLocale: activeLanguageCode,
    );
    invalidateGenreWeights();
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

  static Future<List<int>> getLikedGenreIds() async {
    final weights = await getGenreWeights();
    final sorted = weights.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => e.key).toList();
  }

  /// Tür ağırlık dağılımından, ağırlıkla orantılı olasılıkla [count] FARKLI
  /// tür örnekler (yerine koymadan). Hep aynı "top-3 tür" sorgusu yerine
  /// güne/tura bağlı bir [rng] ile çağrılırsa keşif havuzu çeşitlenir:
  /// 4-5. sıradaki türler de ara sıra vitrine aday üretir. Pozitif ağırlıklı
  /// tür sayısı yetersizse klasik getLikedGenreIds'e düşer.
  static Future<List<int>> sampleLikedGenreIds(
    Random rng, {
    int count = 3,
  }) async {
    final weights = await getGenreWeights();
    final positive = weights.entries.where((e) => e.value > 0).toList();
    if (positive.length <= count) {
      return getLikedGenreIds();
    }
    final pool = List.of(positive);
    final picked = <int>[];
    while (picked.length < count && pool.isNotEmpty) {
      final total = pool.fold<double>(0.0, (s, e) => s + e.value);
      var t = rng.nextDouble() * total;
      var idx = pool.length - 1;
      for (var i = 0; i < pool.length; i++) {
        t -= pool[i].value;
        if (t <= 0) {
          idx = i;
          break;
        }
      }
      picked.add(pool[idx].key);
      pool.removeAt(idx);
    }
    return picked;
  }

  // ─── Öneri gösterim hafızası (impression cooldown) ─────────────────────────
  // "Dün gösterdik, etkileşmedi" sinyali: vitrine/raya çıkan yapımlar kısa bir
  // süre skor cezası alır ki her açılışta aynı yüzler dizilmesin. Yalnızca
  // cihazda tutulur; boyut sınırlı, eski kayıtlar kendiliğinden budanır.

  static const _keyRecoImpressions = 'reco_impressions_v1';
  static const _keyTonightHistory = 'tonight_history_v1';

  static Future<Map<String, int>> _getTimestampMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? '{}';
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _recordTimestamps(
    String prefKey,
    List<String> keys, {
    required int maxAgeMs,
    required int maxEntries,
  }) async {
    if (keys.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    var data = await _getTimestampMap(prefKey);
    for (final k in keys) {
      data[k] = now;
    }
    data.removeWhere((_, v) => now - v > maxAgeMs);
    if (data.length > maxEntries) {
      final entries = data.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      data = Map.fromEntries(entries.take(maxEntries));
    }
    await prefs.setString(prefKey, jsonEncode(data));
  }

  /// key → son gösterim (ms). 14 gün pencere, en fazla 400 kayıt.
  static Future<Map<String, int>> getRecoImpressions() =>
      _getTimestampMap(_keyRecoImpressions);

  static Future<void> recordRecoImpressions(List<String> keys) =>
      _recordTimestamps(
        _keyRecoImpressions,
        keys,
        maxAgeMs: 14 * 24 * 3600 * 1000,
        maxEntries: 400,
      );

  /// Vitrin ("Bu Gece Ne İzlesem?") geçmişi: aynı yapım 7 gün içinde tekrar
  /// vitrin olmasın diye ayrı ve daha uzun pencereli tutulur.
  static Future<Map<String, int>> getTonightHistory() =>
      _getTimestampMap(_keyTonightHistory);

  static Future<void> recordTonightPick(String key) => _recordTimestamps(
    _keyTonightHistory,
    [key],
    maxAgeMs: 30 * 24 * 3600 * 1000,
    maxEntries: 60,
  );

  static Map<int, double>? _cachedGenreWeights;

  static void invalidateGenreWeights() {
    _cachedGenreWeights = null;
  }

  static Future<Map<int, double>> getGenreWeights() async {
    if (_cachedGenreWeights != null) {
      return _cachedGenreWeights!;
    }
    final weights = await _calculateGenreWeights();
    _cachedGenreWeights = weights;
    return weights;
  }

  static Future<Map<int, double>> _calculateGenreWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, double> weights = {};

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Onboarding tür tercihleri: +1.0, ÇOK yavaş decay (~2 yıl yarı ömür).
    // Puanlar ~180 günde sönerken anket hiç sönmezse, pasif kullanıcıda ilk
    // gün işaretlenen kutular zamanla göreli güç kazanıyordu. Yavaş decay
    // cold-start çıpasını korur (30. günde ~0.97) ama süresiz saltanatı bitirir.
    final initialRaw = prefs.getString(_keyInitialGenres) ?? '[]';
    final initialGenres = jsonDecode(initialRaw) as List<dynamic>;
    if (initialGenres.isNotEmpty) {
      var savedAt = prefs.getInt(_keyInitialGenresSavedAt);
      if (savedAt == null) {
        // Eski kurulum: referans anı yok — bu andan itibaren saymaya başla.
        savedAt = now;
        await prefs.setInt(_keyInitialGenresSavedAt, savedAt);
      }
      final surveyDays = (now - savedAt) / (24 * 3600 * 1000);
      final surveyDecay = exp(-0.00095 * surveyDays);
      for (final id in initialGenres) {
        weights[id as int] = (weights[id] ?? 0.0) + (1.0 * surveyDecay);
      }
    }

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

    // 3. Puanlamalardan elde edilen türler (Negatif cezalandırma) * time decay - LIGHTWEIGHT query
    final ratings = await db.getRatingsForWeights();
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

  static Future<void> addToWatchlist(Movie movie) async {
    await DatabaseHelper().addToWatchlist(
      movie,
      metadataLocale: activeLanguageCode,
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

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = null;
    await prefs.clear();
    await _secureStorage.deleteAll();
    await DatabaseHelper().clearAllData();
  }

  // ─── Authentication & Sync ──────────────────────────────────────────────────
  static const _keyAccessToken = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyLastSyncTime = 'sync_last_time';
  static const _keyLastPushTime = 'sync_last_push_time';
  static const _keyUserData = 'auth_user_data';

  // Secure storage okumak (özellikle Android Keystore) her HTTP isteğinde
  // pahalı; access token bellekte cache'lenir. saveTokens/clearAuthData günceller.
  static String? _cachedAccessToken;

  static Future<String?> getAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;

    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyAccessToken);
    if (token != null) {
      _cachedAccessToken = token;
      return token;
    }

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyAccessToken);
    if (token != null) {
      await _secureStorage.write(key: _keyAccessToken, value: token);
      await prefs.remove(_keyAccessToken);
      _cachedAccessToken = token;
    }
    return token;
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    _cachedAccessToken = accessToken;
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

  /// Push imleci: CİHAZ saatiyle tutulur (pull imleci ise sunucu saatiyle).
  /// Eski kurulumlarda anahtar yoksa mevcut davranışı korumak için
  /// sync_last_time'a düşer.
  static Future<int> getLastPushTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastPushTime) ??
        prefs.getInt(_keyLastSyncTime) ??
        0;
  }

  static Future<void> setLastPushTime(int time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastPushTime, time);
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

  static const _keyLastAuthenticatedUserId = 'last_authenticated_user_id';

  static Future<String?> getLastAuthenticatedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastAuthenticatedUserId);
  }

  static Future<void> setLastAuthenticatedUserId(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(_keyLastAuthenticatedUserId);
    } else {
      await prefs.setString(_keyLastAuthenticatedUserId, userId);
    }
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = null;
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
    await prefs.remove(_keyLastSyncTime);
    await prefs.remove(_keyLastPushTime);
    await clearDnaCache();
  }

  // ─── DNA Caching ─────────────────────────────────────────────────────────────
  static const _keyLastDnaJson = 'last_dna_json';
  static const _keyLastDnaInputHash = 'last_dna_input_hash';
  static const _keyLastPublishedDnaHash = 'last_published_dna_hash';

  static Future<Map<String, String>?> getCachedDna() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyLastDnaJson);
    final hash = prefs.getString(_keyLastDnaInputHash);
    if (json != null && hash != null) {
      return {'json': json, 'hash': hash};
    }
    return null;
  }

  static Future<void> cacheDna(String json, String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastDnaJson, json);
    await prefs.setString(_keyLastDnaInputHash, hash);
  }

  static Future<String?> getLastPublishedDnaHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastPublishedDnaHash);
  }

  static Future<void> setLastPublishedDnaHash(String? hash) async {
    final prefs = await SharedPreferences.getInstance();
    if (hash == null) {
      await prefs.remove(_keyLastPublishedDnaHash);
    } else {
      await prefs.setString(_keyLastPublishedDnaHash, hash);
    }
  }

  static Future<void> clearDnaCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastDnaJson);
    await prefs.remove(_keyLastDnaInputHash);
    await prefs.remove(_keyLastPublishedDnaHash);
  }

  // ─── DNA eşik anları (swipe akışındaki keşif kartı) ─────────────────────
  // DNA'nın tek girişi Profil sekmesindeki banner'dı; çekirdek döngüde (swipe)
  // yaşayan kullanıcı özelliğin varlığını hiç öğrenmiyordu. Bu eşikler,
  // puanlama sayısı büyürken DNA'yı bir kez davetle keşfettirir.

  /// İlk eşik, DNA'nın kilidinin açıldığı 5 puanla (bkz. DnaLockedCard) aynı.
  static const dnaMilestones = [5, 25, 50];
  static const _keyDnaMilestonesShown = 'dna_milestones_shown_v1';

  /// [ratingCount] için gösterilmemiş en YÜKSEK eşik; hepsi gösterildiyse
  /// veya sayı ilk eşiğin altındaysa null.
  static Future<int?> pendingDnaMilestone(int ratingCount) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getStringList(_keyDnaMilestonesShown) ?? const [];
    for (final t in dnaMilestones.reversed) {
      if (ratingCount >= t && !shown.contains('$t')) return t;
    }
    return null;
  }

  /// [threshold] ve altındaki TÜM eşikleri gösterildi sayar: 50'nin kartını
  /// gören kullanıcıya sonradan 5'inki gösterilmez.
  static Future<void> markDnaMilestoneShown(int threshold) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getStringList(_keyDnaMilestonesShown) ?? const [];
    final updated = <String>{
      ...shown,
      for (final t in dnaMilestones)
        if (t <= threshold) '$t',
    };
    await prefs.setStringList(_keyDnaMilestonesShown, updated.toList());
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
    final first = prefs.getBool('first_time_dice') ?? true;
    if (first) {
      await prefs.setBool('first_time_dice', false);
    }
    return first;
  }
}
