import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../db_helper.dart';
import 'app_settings.dart';

/// Zevk sinyalleri: tür ağırlıkları, benzerlik, öneri telemetrisi/gösterim
/// hafızası, dismiss geri bildirimi ve DNA cache + eşikleri.
///
/// Public çağrı yüzeyi hâlâ [PrefsService]; bu sınıf taşıma hedefidir.
///
/// Cycle kuralı: bu dosya `prefs_service.dart` import ETMEZ. Favoriler henüz
/// `PrefsService` altında olduğundan (Task 6'ya kadar), tür ağırlığı hesabı
/// favori sırası formülünü kendi içinde geçici olarak kopyalar; Task 6'da
/// `PrefsLibraryFacade.favoriteRankWeight` tek kaynağa indirgenecek.
class PrefsTastePrefs {
  // ─── Favori sıra ağırlığı (geçici kopya — bkz. sınıf dokümanı) ────────────

  static const _favoritesCap = 20;
  static const _favoriteGenreBase = 3.0;

  static double _favoriteRankWeight(int rank) {
    final r = rank.clamp(0, _favoritesCap - 1);
    return 1.0 - 0.8 * (r / (_favoritesCap - 1));
  }

  // ─── Tür ağırlıkları ────────────────────────────────────────────────────────

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
      final double w = _favoriteGenreBase * _favoriteRankWeight(rank);
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

  // ─── Öneri isabet telemetrisi ────────────────────────────────────────────────
  // Kaynak bazında (discover/seed/friend) kaç öneri gösterilip kaçının
  // İyi/Harika aldığını sayar. Motorun gerçek başarısını ölçmenin tek yolu:
  // "önerdik → beğendi mi?" dönüşümü. Yalnızca cihazda tutulur.

  static const _keyRecoTelemetry = 'reco_telemetry_v1';
  static Future<void> _recoTelemetryTail = Future<void>.value();

  static Future<void> _enqueueRecoTelemetry(Future<void> Function() operation) {
    final previous = _recoTelemetryTail;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later telemetry updates.
      }
      await operation();
    }();
    _recoTelemetryTail = current;
    return current;
  }

  static int _asInt(Object? v) =>
      v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  static Future<void> recordRecoOutcome({
    required String source,
    required bool liked,
  }) {
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
      final decoded = jsonDecode(raw);
      final Map<String, dynamic> data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {};
      final srcVal = data[source];
      final Map<String, dynamic> bucket = srcVal is Map
          ? Map<String, dynamic>.from(srcVal)
          : {'shown': 0, 'liked': 0};
      bucket['shown'] = _asInt(bucket['shown']) + 1;
      if (liked) bucket['liked'] = _asInt(bucket['liked']) + 1;
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  static Future<void> revertRecoOutcome({
    required String source,
    required bool liked,
  }) {
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
      final decoded = jsonDecode(raw);
      final Map<String, dynamic> data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {};
      final srcVal = data[source];
      final Map<String, dynamic> bucket = srcVal is Map
          ? Map<String, dynamic>.from(srcVal)
          : {'shown': 0, 'liked': 0};
      final shown = _asInt(bucket['shown']);
      final currentLiked = _asInt(bucket['liked']);
      if (shown > 0) {
        bucket['shown'] = shown - 1;
      }
      if (liked && currentLiked > 0) {
        bucket['liked'] = currentLiked - 1;
      }
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// Kaynak → {shown, liked} sayaçları. Beğeni oranı = liked/shown.
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRecoTelemetry) ?? '{}';
    final decoded = jsonDecode(raw);
    final Map<String, dynamic> data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : {};
    return data.map(
      (k, v) => MapEntry(
        k,
        v is Map
            ? Map<String, dynamic>.from(
                v,
              ).map((k2, v2) => MapEntry(k2, _asInt(v2)))
            : <String, int>{},
      ),
    );
  }

  static const _keyDismissFeedback = 'dismiss_feedback_v1';
  static const _keyDismissCount = 'dismiss_feedback_count_v1';
  static const _keyDismissLastAsked = 'dismiss_feedback_last_asked_v1';

  static Future<bool> shouldAskDismissFeedback({
    required int matchScore,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_keyDismissCount) ?? 0) + 1;
    await prefs.setInt(_keyDismissCount, count);
    final lastAsked = prefs.getInt(_keyDismissLastAsked) ?? 0;
    final cooldownPassed =
        DateTime.now().millisecondsSinceEpoch - lastAsked >
        const Duration(hours: 24).inMilliseconds;
    final shouldAsk = cooldownPassed && (matchScore >= 75 || count % 4 == 0);
    if (shouldAsk) {
      await prefs.setInt(
        _keyDismissLastAsked,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    return shouldAsk;
  }

  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDismissFeedback) ?? '[]';
    final decoded = jsonDecode(raw);
    final events = decoded is List
        ? decoded
              .whereType<Map<Object?, Object?>>()
              .map(Map<String, dynamic>.from)
              .toList()
        : <Map<String, dynamic>>[];
    events.add({
      'movie_key': movieKey,
      'reason': reason,
      'source': source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    if (events.length > 100) events.removeRange(0, events.length - 100);
    await prefs.setString(_keyDismissFeedback, jsonEncode(events));
  }

  static Future<List<Map<String, dynamic>>> getDismissFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString(_keyDismissFeedback) ?? '[]');
    return decoded is List
        ? decoded
              .whereType<Map<Object?, Object?>>()
              .map(Map<String, dynamic>.from)
              .toList()
        : const [];
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

  // ─── Bellek içi cache sıfırlama ─────────────────────────────────────────────

  static void resetInMemoryCaches() {
    _recoTelemetryTail = Future<void>.value();
    invalidateGenreWeights();
  }
}
