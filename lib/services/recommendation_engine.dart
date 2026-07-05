import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'tmdb_service.dart';

/// Skorlanmış aday — sıralama boyunca ham skoru filmle birlikte taşır.
class ScoredMovie {
  final Movie movie;
  double score;
  ScoredMovie(this.movie, this.score);
}

/// Cihaz üstü öneri motoru — swipe kuyruğu ve "Sana Özel" rayının ortak beyni.
///
/// Boru hattı (recall → rank):
///  1. Aday toplama: tür-bazlı discover + son "Harika"lardan TMDB
///     similar/recommendations (seed) + arkadaş sinyalleri (boost).
///  2. Kaba sıralama: tür kosinüs benzerliği + TMDB puanı harmanı.
///  3. Hassas re-rank: görünecek ilk dilim (top-K) keyword zevk vektörüyle
///     yeniden puanlanır.
///  4. Çeşitlilik (MMR-lite): birbirinin kopyası türdeki adaylar cezalandırılır
///     ki ray tek tip görünmesin.
///  5. Gerekçe atıfı: her adaya "neden önerildi" etiketi (seed adı / arkadaş
///     adı) yazılır — UI'daki "seni tanıyor" hissinin taşıyıcısı.
class RecommendationEngine {
  final TmdbService _service;

  RecommendationEngine(this._service);

  /// Kullanıcının anahtar kelime zevk vektörü (keyword_id → ağırlık).
  /// Beğenilen (İyi/Harika) yapımların keyword'lerinden kurulur, memoize
  /// edilir; her rate/undo'da [invalidateTasteVector] ile sıfırlanır.
  Map<int, double>? _userKeywordVector;

  /// Zevk profili değişti (puan verildi / geri alındı) — vektör yeniden kurulsun.
  void invalidateTasteVector() => _userKeywordVector = null;

  // ── Harman ağırlıkları (tek doğruluk kaynağı) ─────────────────────────────
  /// Keyword sinyali yokken: tür lider, TMDB puanı taban.
  static const genreOnlyWeights = (genre: 0.7, vote: 0.3);

  /// Keyword sinyali varken: tür lider, keyword güçlü ikinci, puan taban.
  static const fullWeights = (genre: 0.45, keyword: 0.25, vote: 0.3);

  /// Ham skor harmanı. [kwSim] null ise keyword fazı atlanır.
  static double blend({
    required double genreSim,
    double? kwSim,
    required double voteAverage,
  }) {
    final vote = voteAverage / 10.0;
    if (kwSim == null) {
      return genreOnlyWeights.genre * genreSim + genreOnlyWeights.vote * vote;
    }
    return fullWeights.genre * genreSim +
        fullWeights.keyword * kwSim +
        fullWeights.vote * vote;
  }

  /// Ham skoru kullanıcıya gösterilen uyum yüzdesine [40, 98] eşler.
  /// Sigmoid 0.2 (cold-start ortalaması) merkezlidir; 98 tavanı "sahte %100"
  /// vaadini engeller.
  static int toDisplayScore(double raw) {
    final z = (raw - 0.2) * 4.0;
    final sigmoid = 1.0 / (1.0 + exp(-z));
    return (40 + (sigmoid * 58)).round().clamp(40, 98);
  }

  /// Arkadaş sinyali boost'u: sinyal başına +[perFriend], en fazla [maxFriends]
  /// arkadaş sayılır. Gerekçe olarak ilk arkadaşın adı yazılır (sosyal kanıt,
  /// seed gerekçesinden daha kişiseldir — onu ezer).
  static void applyFriendSignals(
    List<ScoredMovie> scored,
    Map<String, List<String>> signals, {
    double perFriend = 0.06,
    int maxFriends = 3,
  }) {
    if (signals.isEmpty) return;
    for (final s in scored) {
      final key = "${s.movie.isTV ? 'tv' : 'movie'}_${s.movie.id}";
      final friends = signals[key];
      if (friends == null || friends.isEmpty) continue;
      s.score += perFriend * min(friends.length, maxFriends);
      s.movie
        ..recoReason = friends.first
        ..recoReasonType = 'friend'
        ..recoSource = 'friend';
    }
  }

  /// İki id listesinin Jaccard benzerliği: |kesişim| / |birleşim|.
  /// Tür ve keyword kümeleri için ortak yardımcı.
  static double jaccard(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final sa = a.toSet();
    final sb = b.toSet();
    final inter = sa.intersection(sb).length;
    final union = sa.union(sb).length;
    return union == 0 ? 0.0 : inter / union;
  }

  /// MMR-lite çeşitlilik geçişi: her adım en yüksek "ayarlı" skorlu adayı seçer;
  /// ayarlı skor = ham skor − [lambda] × (seçilmişlerle en yüksek tür Jaccard
  /// benzerliği). Böylece art arda aynı tür kombinasyonu dizilmez ama güçlü
  /// adaylar da kaybolmaz.
  static List<ScoredMovie> applyDiversity(
    List<ScoredMovie> scored, {
    double lambda = 0.12,
  }) {
    if (scored.length <= 2) return List.of(scored);
    final remaining = List.of(scored)
      ..sort((a, b) => b.score.compareTo(a.score));
    final picked = <ScoredMovie>[];

    while (remaining.isNotEmpty) {
      ScoredMovie? best;
      double bestAdj = double.negativeInfinity;
      for (final cand in remaining) {
        double maxSim = 0.0;
        // Yalnız son seçilen birkaç öğeyle kıyas yeter (yerel monotonluk kırma).
        for (final p in picked.reversed.take(4)) {
          final sim = jaccard(cand.movie.genreIds, p.movie.genreIds);
          if (sim > maxSim) maxSim = sim;
        }
        final adj = cand.score - lambda * maxSim;
        if (adj > bestAdj) {
          bestAdj = adj;
          best = cand;
        }
      }
      picked.add(best!);
      remaining.remove(best);
    }
    return picked;
  }

  /// Beğenilen (rating>=2) yapımların keyword'lerinden kullanıcı zevk vektörünü
  /// kurar. Harika(3)→+2, İyi(2)→+1, zaman decay'li (~180 gün yarı ömür, prefs
  /// tür ağırlıklarıyla aynı). En yeni 15 beğeni ile sınırlıdır; keyword uçları
  /// cache'li olduğundan tekrar çağrılarda ağ maliyeti ~sıfırdır.
  Future<Map<int, double>> buildUserKeywordVector() async {
    final cached = _userKeywordVector;
    if (cached != null) return cached;

    final vec = <int, double>{};
    try {
      final ratings = await DatabaseHelper().getRatings();
      final liked = ratings.where((r) => (r['rating'] as int) >= 2).toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );
      final seeds = liked.take(15).toList();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final kwLists = await Future.wait(
        seeds.map((r) {
          final id = r['id'] as int;
          final isTV = r['isTV'] as bool? ?? false;
          return _service
              .getKeywordIds(id, isTV: isTV)
              .catchError((_) => <int>[]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final r = seeds[i];
        final rating = r['rating'] as int;
        final base = rating == 3 ? 2.0 : 1.0; // Harika daha güçlü
        final createdAt = r['created_at'] as int;
        final days = (nowMs - createdAt) / 86400000.0;
        final decay = exp(-0.00385 * days);
        final w = base * decay;
        for (final kid in kwLists[i]) {
          vec[kid] = (vec[kid] ?? 0.0) + w;
        }
      }
    } catch (e, st) {
      debugPrint("Error calculating keyword vector: $e\n$st");
      // Hata → boş vektör; keyword fazı sessizce atlanır (cold-start gibi).
    }

    _userKeywordVector = vec;
    return vec;
  }

  /// Son [seedCount] "Harika" (rating=3) yapımı tohum yapıp TMDB
  /// recommendations + similar uçlarından aday toplar. Her adaya gerekçe
  /// olarak tohumun adı yazılır ("X'i beğendiğin için").
  Future<List<Movie>> fetchSeedCandidates({int seedCount = 3}) async {
    final candidates = <Movie>[];
    try {
      final ratings = await DatabaseHelper().getRatings();
      final highRated = ratings.where((r) => r['rating'] == 3).toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );
      final seeds = highRated.take(seedCount).toList();
      if (seeds.isEmpty) return candidates;

      final results = await Future.wait(
        seeds.map((s) {
          final int id = s['id'] as int;
          final bool isTV = s['isTV'] as bool? ?? false;
          return Future.wait([
            _service.getRecommendations(id, isTV: isTV),
            _service.getSimilar(id, isTV: isTV),
          ]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final seedTitle = (seeds[i]['movie'] as Movie?)?.title ?? '';
        for (final list in results[i]) {
          for (final m in list) {
            m
              ..recoReason = seedTitle.isNotEmpty ? seedTitle : null
              ..recoReasonType = seedTitle.isNotEmpty ? 'seed' : null
              ..recoSource = 'seed';
            candidates.add(m);
          }
        }
      }
    } catch (e, st) {
      debugPrint("Failed to load similar/recommendation seeds: $e\n$st");
    }
    return candidates;
  }

  /// Tam sıralama boru hattı. [candidates] içinden puanlanmış/engellenmişler
  /// [excludedKeys] ile ayıklanır, tür benzerliğiyle kaba sıralanır, ilk
  /// [rerankK] aday keyword vektörüyle yeniden puanlanır, arkadaş sinyalleri
  /// eklenir ve çeşitlilik geçişi uygulanır. Dönen listedeki her filmde
  /// `personalizedMatchScore` (ve varsa `recoReason`) doldurulmuş olur.
  Future<List<Movie>> rankForYou(
    List<Movie> candidates, {
    Set<String> excludedKeys = const {},
    Map<String, List<String>> friendSignals = const {},
    int rerankK = 20,
    bool diversify = true,
  }) async {
    // Tekilleştir + dışlananları ele.
    final seen = <String>{};
    final fresh = <Movie>[];
    for (final m in candidates) {
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
      if (!excludedKeys.contains(key) && seen.add(key)) fresh.add(m);
    }
    if (fresh.isEmpty) return fresh;

    final userWeights = await PrefsService.getGenreWeights();

    // Kaba sıralama: tür + puan.
    final scored = <ScoredMovie>[];
    for (final m in fresh) {
      final genreSim = PrefsService.calculateSimilarity(
        userWeights,
        m.genreIds,
      );
      final raw = blend(genreSim: genreSim, voteAverage: m.voteAverage);
      m.personalizedMatchScore = toDisplayScore(raw);
      m.recoSource ??= 'discover';
      scored.add(ScoredMovie(m, raw));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Hassas re-rank: görünecek ilk dilimi keyword zevkiyle yeniden puanla.
    final kwVector = await buildUserKeywordVector();
    if (kwVector.isNotEmpty) {
      final k = min(rerankK, scored.length);
      final top = scored.sublist(0, k);
      final kwLists = await Future.wait(
        top.map(
          (s) => _service
              .getKeywordIds(s.movie.id, isTV: s.movie.isTV)
              .catchError((_) => <int>[]),
        ),
      );
      for (var i = 0; i < top.length; i++) {
        final m = top[i].movie;
        final genreSim = PrefsService.calculateSimilarity(
          userWeights,
          m.genreIds,
        );
        final kwSim = PrefsService.calculateSimilarity(kwVector, kwLists[i]);
        final raw = blend(
          genreSim: genreSim,
          kwSim: kwSim,
          voteAverage: m.voteAverage,
        );
        m.personalizedMatchScore = toDisplayScore(raw);
        top[i].score = raw;
      }
    }

    // Sosyal kanıt: arkadaş sinyali olan adayları yükselt + gerekçele.
    applyFriendSignals(scored, friendSignals);

    scored.sort((a, b) => b.score.compareTo(a.score));
    final ordered = diversify ? applyDiversity(scored) : scored;
    return ordered.map((s) => s.movie).toList();
  }

  // ── "Benzer film bul" (anchor-tabanlı benzerlik) ─────────────────────────

  /// Benzerlik harmanı: keyword örtüşmesi lider (tema benzerliği türden
  /// güçlüdür), tür ikinci, co-visitation (TMDB recommendations'tan gelme)
  /// davranışsal bonus, TMDB puanı kalite tabanı.
  static double similarityScore({
    required double kwJaccard,
    required double genreJaccard,
    required bool coVisit,
    required double voteAverage,
  }) {
    return 0.45 * kwJaccard +
        0.20 * genreJaccard +
        0.15 * (coVisit ? 1.0 : 0.0) +
        0.20 * (voteAverage / 10.0);
  }

  /// Karşılaştırma için başlık normalizasyonu (küçük harf, noktalama sız).
  static String _normTitle(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9çğıöşü ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Skor sırasına dizilmiş listede aynı seriden (birinin normalize başlığı
  /// diğerinin öneki) yalnızca en iyi skorluyu tutar: "Iron Man" kalır,
  /// "Iron Man 2/3" elenir. 5 karakterden kısa başlıklar (Up, Se7en gibi
  /// yanlış pozitif riski) muaftır.
  static List<Movie> suppressFranchiseDuplicates(List<Movie> ordered) {
    final kept = <Movie>[];
    final keptNorms = <String>[];
    for (final m in ordered) {
      final n = _normTitle(m.title);
      final isDup =
          n.length >= 5 &&
          keptNorms.any(
            (k) => k.length >= 5 && (n.startsWith(k) || k.startsWith(n)),
          );
      if (!isDup) {
        kept.add(m);
        keptNorms.add(n);
      }
    }
    return kept;
  }

  /// [anchor] filmine benzeyen adayları sıralar ("Benzer film bul").
  ///
  /// Boru hattı: tekilleştir + dışla → anchor'ın serisini ele (kullanıcı
  /// sevdiği filmin devamlarını zaten bilir; keşif istiyor) → ilk [keywordK]
  /// adayı anchor'ın keyword kümesiyle Jaccard'la puanla → harman skoru →
  /// seri kopyalarını bastır. [coVisitKeys], recommendations ucundan gelen
  /// (birlikte izlenme sinyalli) adayların anahtarları.
  Future<List<Movie>> rankSimilarTo(
    Movie anchor, {
    required List<Movie> candidates,
    Set<String> excludedKeys = const {},
    Set<String> coVisitKeys = const {},
    int keywordK = 30,
  }) async {
    final anchorNorm = _normTitle(anchor.title);
    final seen = <String>{};
    final fresh = <Movie>[];
    for (final m in candidates) {
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
      if (excludedKeys.contains(key) || !seen.add(key)) continue;
      // Anchor'ın kendi serisi keşif değildir → ele.
      final n = _normTitle(m.title);
      if (anchorNorm.length >= 5 &&
          n.length >= 5 &&
          (n.startsWith(anchorNorm) || anchorNorm.startsWith(n))) {
        continue;
      }
      fresh.add(m);
    }
    if (fresh.isEmpty) return fresh;

    List<int> anchorKeywords = const [];
    try {
      anchorKeywords = await _service.getKeywordIds(
        anchor.id,
        isTV: anchor.isTV,
      );
    } catch (e) {
      debugPrint("Anchor keywords unavailable, genre-only similarity: $e");
    }

    // Keyword isteği pahalı olduğundan yalnız öncü dilime uygulanır; dilim,
    // ucuz sinyallerle (co-visit + tür + puan) öne çekilerek seçilir.
    fresh.sort((a, b) {
      double cheap(Movie m) => similarityScore(
        kwJaccard: 0,
        genreJaccard: jaccard(anchor.genreIds, m.genreIds),
        coVisit: coVisitKeys.contains("${m.isTV ? 'tv' : 'movie'}_${m.id}"),
        voteAverage: m.voteAverage,
      );
      return cheap(b).compareTo(cheap(a));
    });

    final k = min(keywordK, fresh.length);
    final kwLists = anchorKeywords.isEmpty
        ? List<List<int>>.filled(k, const [])
        : await Future.wait(
            fresh
                .take(k)
                .map(
                  (m) => _service
                      .getKeywordIds(m.id, isTV: m.isTV)
                      .catchError((_) => <int>[]),
                ),
          );

    final scored = <ScoredMovie>[];
    for (var i = 0; i < fresh.length; i++) {
      final m = fresh[i];
      final kwSim = i < k && anchorKeywords.isNotEmpty
          ? jaccard(anchorKeywords, kwLists[i])
          : 0.0;
      scored.add(
        ScoredMovie(
          m,
          similarityScore(
            kwJaccard: kwSim,
            genreJaccard: jaccard(anchor.genreIds, m.genreIds),
            coVisit: coVisitKeys.contains("${m.isTV ? 'tv' : 'movie'}_${m.id}"),
            voteAverage: m.voteAverage,
          ),
        ),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return suppressFranchiseDuplicates(scored.map((s) => s.movie).toList());
  }
}
