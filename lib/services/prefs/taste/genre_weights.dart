import 'dart:convert';
import 'dart:math';

import '../../db_helper.dart';
import '../app_settings.dart';
import '../favorite_weights.dart';

/// Tür ağırlıkları: onboarding anketi, favoriler ve puanlardan çıkarılan
/// kullanıcı zevk vektörü, kosinüs benzerliği ve türetilmiş beğenilen türler.
///
/// Public çağrı yüzeyi hâlâ [PrefsTastePrefs]; bu sınıf taşıma hedefidir.
///
/// Cycle kuralı: bu dosya `prefs_service.dart` import ETMEZ.
class PrefsGenreWeights {
  static Map<int, double>? _cachedGenreWeights;

  static void invalidateGenreWeights() {
    _cachedGenreWeights = null;
  }

  static Future<void> resetOnboarding() async {
    await PrefsAppSettings.resetOnboarding();
    invalidateGenreWeights();
  }

  static Future<void> saveInitialGenres(List<int> genreIds) async {
    await PrefsAppSettings.saveInitialGenres(genreIds);
    invalidateGenreWeights();
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
    final Map<int, double> weights = {};

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Onboarding tür tercihleri: +1.0, ÇOK yavaş decay (~2 yıl yarı ömür).
    // Puanlar ~180 günde sönerken anket hiç sönmezse, pasif kullanıcıda ilk
    // gün işaretlenen kutular zamanla göreli güç kazanıyordu. Yavaş decay
    // cold-start çıpasını korur (30. günde ~0.97) ama süresiz saltanatı bitirir.
    final initialGenres = await PrefsAppSettings.getInitialGenres();
    if (initialGenres.isNotEmpty) {
      var savedAt = await PrefsAppSettings.getInitialGenresSavedAt();
      if (savedAt == null) {
        // Eski kurulum: referans anı yok — bu andan itibaren saymaya başla.
        savedAt = now;
        await PrefsAppSettings.setInitialGenresSavedAt(savedAt);
      }
      final surveyDays = (now - savedAt) / (24 * 3600 * 1000);
      final surveyDecay = exp(-0.00095 * surveyDays);
      for (final id in initialGenres) {
        weights[id] = (weights[id] ?? 0.0) + (1.0 * surveyDecay);
      }
    }

    final db = DatabaseHelper();

    // 2. Favori film ve diziler: rank-ağırlıklı KALICI çıpa (zaman decay'i YOK).
    // created_at, favorinin liste içi 0-tabanlı sırasıdır (#1 = 0). "Hayatımın
    // yapımları" bayatlamaz; sıra ağırlığı uygulanır: #1 tam +3.0, sona doğru
    // azalır. (Eskiden created_at yanlışlıkla zaman damgası sanılıp decay ~0'a
    // çöküyor, favorilerin tür sinyali cihazda tümüyle ölüyordu.)
    final favorites = await db.getFavoritesRaw();
    for (final fav in favorites) {
      final String genreIdsRaw = fav['genre_ids'] as String? ?? '[]';
      final decodedGenreIds = jsonDecode(genreIdsRaw);
      final List<dynamic> genreIds = decodedGenreIds is List
          ? decodedGenreIds
          : const [];
      final int rank = fav['created_at'] as int? ?? 0;
      final double w = favoriteGenreBase * favoriteRankWeight(rank);
      for (final id in genreIds) {
        if (id is int) {
          weights[id] = (weights[id] ?? 0.0) + w;
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
}
