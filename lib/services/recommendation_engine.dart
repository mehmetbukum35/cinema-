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
///  2. Kaba sıralama: tür kosinüs benzerliği + TMDB puanı harmanı; birden
///     fazla tohumun benzerlerinde geçen adaya kesişim bonusu eklenir.
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
  Map<int, double>? _userKeywordVector;

  /// Kullanıcı oylama listesinin bellek önbelleği.
  List<Map<String, dynamic>>? _cachedRatings;

  /// Beğenilmeyen (Eh/Berbat) filmlerin benzer/öneri anahtar kelime önbelleği.
  (Set<String> berbatKeys, Set<String> ehKeys)? _cachedNegativeKeys;

  /// Zevk profili değişti veya senkronizasyon yapıldı — önbelleği temizle.
  Future<void> invalidateCache({bool isNegativeChange = true}) async {
    _userKeywordVector = null;
    _cachedRatings = null;
    if (isNegativeChange) {
      _cachedNegativeKeys = null;
    }
    await PrefsService.clearDnaCache();
  }

  /// Eski çağrılar için geriye dönük uyumluluk metodu.
  Future<void> invalidateTasteVector() async {
    await invalidateCache();
  }

  /// Oylamaları bellekten veya veritabanından çeken yardımcı metot.
  Future<List<Map<String, dynamic>>> _getRatings() async {
    final cached = _cachedRatings;
    if (cached != null) return cached;
    final ratings = await DatabaseHelper().getRatings();
    _cachedRatings = ratings;
    return ratings;
  }

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

  /// Çoklu tohum kesişimi bonusu: aday kaç FARKLI tohumun benzer/öneri
  /// listesinde göründüyse, ilkinden sonraki her tohum için +[perSeed] alır
  /// (en fazla [maxSeeds] tohum sayılır). Tek tohumdan gelen aday bonus almaz;
  /// böylece seed/discover dengesi bozulmaz ama 2-3 beğeninin kesişimindeki
  /// aday — zevkin ortak noktası, tekil benzerlikten güçlü sinyal — öne çıkar.
  static double seedOverlapBoost(
    int seedCount, {
    double perSeed = 0.05,
    int maxSeeds = 3,
  }) {
    if (seedCount <= 1) return 0.0;
    return perSeed * (min(seedCount, maxSeeds) - 1);
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
      final ratings = await _getRatings();
      // En son 25 oylamayı al (tüm beğenilenler ve beğenilmeyenler dahil)
      final sortedRatings = ratings.toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );
      final seeds = sortedRatings.take(15).toList();
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
        // Harika -> +2.0, İyi -> +1.0, Eh -> -1.0, Berbat -> -2.0
        final double base;
        if (rating == 3) {
          base = 2.0;
        } else if (rating == 2) {
          base = 1.0;
        } else if (rating == 1) {
          base = -1.0;
        } else if (rating == 0) {
          base = -2.0;
        } else {
          continue;
        }

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

  /// Son [seedCount] tohum yapımı (öncelik sırasıyla Harika(3) -> İyi(2) -> Favoriler -> Watchlist)
  /// tohum yapıp TMDB recommendations + similar uçlarından aday toplar.
  /// Her adaya gerekçe olarak tohumun adı yazılır ("X'i beğendiğin için").
  /// Tohum adedi, telemetri verilerine göre dinamik olarak genişletilip daraltılır (Adaptive).
  ///
  /// [rng] verilirse tohumlar "hep en son beğenilenler" yerine son 12 beğeniden
  /// yeniliğe eğilimli ağırlıklı örneklemeyle seçilir: güne bağlı bir rng ile
  /// her gün farklı tohumlar → farklı benzer-film adayları (vitrin tazeliği).
  Future<List<Movie>> fetchSeedCandidates({
    int seedCount = 3,
    Random? rng,
  }) async {
    final candidates = <Movie>[];
    try {
      final db = DatabaseHelper();
      final ratings = await _getRatings();

      int finalSeedCount = seedCount;
      try {
        final telemetry = await PrefsService.getRecoTelemetry();
        final seedBucket = telemetry['seed'] ?? {'shown': 0, 'liked': 0};
        final discoverBucket =
            telemetry['discover'] ?? {'shown': 0, 'liked': 0};

        final double crSeed =
            (seedBucket['liked']! + 1) / (seedBucket['shown']! + 2);
        final double crDiscover =
            (discoverBucket['liked']! + 1) / (discoverBucket['shown']! + 2);

        finalSeedCount = (seedCount * (crSeed / crDiscover)).round().clamp(
          2,
          6,
        );
      } catch (e) {
        debugPrint("Failed to calculate adaptive seedCount from telemetry: $e");
      }

      // 1. Oylamalardan tohumlar: Harika (3) ve İyi (2)
      final harikaSeeds = ratings.where((r) => r['rating'] == 3).toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );
      final iyiSeeds = ratings.where((r) => r['rating'] == 2).toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );

      List<Map<String, dynamic>> ratingSeeds = [...harikaSeeds, ...iyiSeeds];

      // Tohum rotasyonu: rng varsa son 12 beğeniden ağırlıklı örnekle
      // (öndekiler daha olası ama eski favoriler de şans bulur).
      if (rng != null && ratingSeeds.length > finalSeedCount) {
        final window = ratingSeeds.take(12).toList();
        final sampled = <Map<String, dynamic>>[];
        while (sampled.length < finalSeedCount && window.isNotEmpty) {
          final weights = List.generate(window.length, (i) => 1.0 / (i + 2));
          final total = weights.fold<double>(0.0, (s, w) => s + w);
          var t = rng.nextDouble() * total;
          var idx = window.length - 1;
          for (var i = 0; i < window.length; i++) {
            t -= weights[i];
            if (t <= 0) {
              idx = i;
              break;
            }
          }
          sampled.add(window.removeAt(idx));
        }
        ratingSeeds = sampled;
      }

      final seedItems = <({int id, bool isTV, String title})>[];

      for (final r in ratingSeeds) {
        if (seedItems.length >= finalSeedCount) break;
        final movie = r['movie'] as Movie?;
        if (movie != null) {
          seedItems.add((id: movie.id, isTV: movie.isTV, title: movie.title));
        }
      }

      // 2. Eksik kalırsa Favorilerden tohum ekle
      if (seedItems.length < finalSeedCount) {
        final favMovies = await db
            .getFavorites(false)
            .catchError((_) => <Movie>[]);
        final favShows = await db
            .getFavorites(true)
            .catchError((_) => <Movie>[]);
        final allFavs = [...favMovies, ...favShows];
        for (final m in allFavs) {
          if (seedItems.length >= finalSeedCount) break;
          if (seedItems.any((s) => s.id == m.id && s.isTV == m.isTV)) continue;
          seedItems.add((id: m.id, isTV: m.isTV, title: m.title));
        }
      }

      // 3. Hala eksik kalırsa Watchlist'ten tohum ekle
      if (seedItems.length < finalSeedCount) {
        final watchlist = await db.getWatchlist().catchError((_) => <Movie>[]);
        for (final m in watchlist) {
          if (seedItems.length >= finalSeedCount) break;
          if (seedItems.any((s) => s.id == m.id && s.isTV == m.isTV)) continue;
          seedItems.add((id: m.id, isTV: m.isTV, title: m.title));
        }
      }

      if (seedItems.isEmpty) return candidates;

      final results = await Future.wait(
        seedItems.map((s) {
          return Future.wait([
            _service
                .getRecommendations(s.id, isTV: s.isTV)
                .catchError((_) => <Movie>[]),
            _service
                .getSimilar(s.id, isTV: s.isTV)
                .catchError((_) => <Movie>[]),
          ]);
        }),
      );

      for (var i = 0; i < seedItems.length; i++) {
        final seed = seedItems[i];
        for (final list in results[i]) {
          for (final m in list) {
            m
              ..recoReason = seed.title.isNotEmpty ? seed.title : null
              ..recoReasonType = seed.title.isNotEmpty ? 'seed' : null
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

  // ── Keşif dilimi (epsilon-greedy) ─────────────────────────────────────────

  /// "Sana Özel" rayının keşfe ayrılan oranı. Telemetrideki 'explore'
  /// kaynağının beğeni dönüşümü 'discover'a göre iyiyse oran büyür, kötüyse
  /// küçülür (Laplace düzeltmeli; adaptif tohum sayısıyla aynı desen).
  /// Sınırlar [0.05, 0.20]: keşif hiç sıfırlanmaz ama rayı da ele geçirmez.
  Future<double> adaptiveExploreRate({double base = 0.12}) async {
    try {
      final telemetry = await PrefsService.getRecoTelemetry();
      final explore = telemetry['explore'] ?? {'shown': 0, 'liked': 0};
      final discover = telemetry['discover'] ?? {'shown': 0, 'liked': 0};
      final crExplore = (explore['liked']! + 1) / (explore['shown']! + 2);
      final crDiscover = (discover['liked']! + 1) / (discover['shown']! + 2);
      return (base * (crExplore / crDiscover)).clamp(0.05, 0.20);
    } catch (e) {
      debugPrint("adaptiveExploreRate failed, using base: $e");
      return base;
    }
  }

  /// Konfor alanı DIŞI keşif adayları: [pool] (trend/popüler listesi) içinden,
  /// kişisel sıralamaya zaten girmiş ([rankedKeys]) ve dışlanmış
  /// ([excludedKeys]) olanlar elendikten sonra kalite tabanını geçen
  /// (vote >= [minVote]) adaylardan [rng] ile [count] tanesini seçer.
  /// Seçilenler 'explore' kaynağıyla işaretlenir → telemetri döngüsü kapanır.
  List<Movie> pickExplorationCandidates({
    required List<Movie> pool,
    required Set<String> rankedKeys,
    required Set<String> excludedKeys,
    required Random rng,
    required int count,
    double minVote = 6.5,
  }) {
    if (count <= 0) return const [];
    final seen = <String>{};
    final eligible = <Movie>[];
    for (final m in pool) {
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
      if (rankedKeys.contains(key) || excludedKeys.contains(key)) continue;
      if (m.voteAverage < minVote) continue;
      if (!seen.add(key)) continue;
      eligible.add(m);
    }
    eligible.shuffle(rng);
    final picked = eligible.take(count).toList();
    for (final m in picked) {
      m
        ..recoSource = 'explore'
        ..recoReason = null
        ..recoReasonType = null;
    }
    return picked;
  }

  /// Eh/Berbat oylanan yapımların benzerlerini bulup engelleme/ceza seti oluşturur.
  Future<(Set<String> berbatKeys, Set<String> ehKeys)>
  fetchNegativeSeedKeys() async {
    final cached = _cachedNegativeKeys;
    if (cached != null) return cached;

    final berbatKeys = <String>{};
    final ehKeys = <String>{};
    try {
      final ratings = await _getRatings();
      final disliked =
          ratings.where((r) {
            final rating = r['rating'] as int;
            return rating == 0 || rating == 1;
          }).toList()..sort(
            (a, b) =>
                (b['created_at'] as int).compareTo(a['created_at'] as int),
          );
      final seeds = disliked.take(3).toList();
      if (seeds.isEmpty) {
        _cachedNegativeKeys = (berbatKeys, ehKeys);
        return _cachedNegativeKeys!;
      }

      final results = await Future.wait(
        seeds.map((s) {
          final int id = s['id'] as int;
          final bool isTV = s['isTV'] as bool? ?? false;
          return Future.wait([
            _service
                .getRecommendations(id, isTV: isTV)
                .catchError((_) => <Movie>[]),
            _service.getSimilar(id, isTV: isTV).catchError((_) => <Movie>[]),
          ]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final rating = seeds[i]['rating'] as int;
        final targetSet = rating == 0 ? berbatKeys : ehKeys;
        for (final list in results[i]) {
          for (final m in list) {
            targetSet.add("${m.isTV ? 'tv' : 'movie'}_${m.id}");
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch negative seeds: $e");
    }
    _cachedNegativeKeys = (berbatKeys, ehKeys);
    return _cachedNegativeKeys!;
  }

  /// Tam sıralama boru hattı. [candidates] içinden puanlanmış/engellenmişler
  /// [excludedKeys] ile ayıklanır, tür benzerliğiyle kaba sıralanır, ilk
  /// [rerankK] aday keyword vektörüyle yeniden puanlanır, arkadaş sinyalleri
  /// eklenir ve çeşitlilik geçişi uygulanır. Dönen listedeki her filmde
  /// `personalizedMatchScore` (ve varsa `recoReason`) doldurulmuş olur.
  /// [cooldownKeys]: yakın zamanda kullanıcıya GÖSTERİLMİŞ yapımların
  /// anahtarları — küçük bir skor cezası ([cooldownPenalty]) alır ki vitrin ve
  /// ray her açılışta aynı yüzlerle dizilmesin (impression cooldown).
  Future<List<Movie>> rankForYou(
    List<Movie> candidates, {
    Set<String> excludedKeys = const {},
    Map<String, List<String>> friendSignals = const {},
    Set<String> cooldownKeys = const {},
    double cooldownPenalty = 0.08,
    int rerankK = 20,
    bool diversify = true,
    double jitter = 0.0,
    bool suppressFranchises = false,
  }) async {
    // Negatif sinyalleri yükle (similar / recommendations)
    final (berbatKeys, ehKeys) = await fetchNegativeSeedKeys();

    // Berbat (0) oylanan filmlerin franchise/seri isimlerini yükle (Prefix bastırma için)
    final ratings = await _getRatings();
    final berbatTitles = ratings
        .where((r) => (r['rating'] as int) == 0)
        .map((r) => _normTitle((r['movie'] as Movie?)?.title ?? ''))
        .where((t) => t.length >= 5)
        .toList();

    // Çoklu tohum kesişimi: aynı aday kaç FARKLI tohumun benzer/öneri
    // listesinden geldi? Tekilleştirme ilk kopyayı tutup gerisini atacağı
    // için sayım burada, tekilleştirmeden ÖNCE yapılmalı.
    final seedTitlesByKey = <String, Set<String>>{};
    for (final m in candidates) {
      final reason = m.recoReason;
      if (m.recoSource == 'seed' && reason != null) {
        final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
        (seedTitlesByKey[key] ??= <String>{}).add(reason);
      }
    }

    // Tekilleştir + dışlananları ele.
    final seen = <String>{};
    final fresh = <Movie>[];
    for (final m in candidates) {
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";

      // Hard filter: Zaten oylananlar veya sırada olanlar
      if (excludedKeys.contains(key)) continue;

      // Hard filter: Berbat oylanan filmin recommendations/similar havuzunda olanlar
      if (berbatKeys.contains(key)) continue;

      // Hard filter: Berbat oylanan bir filmin devamı/serisi olanlar
      final n = _normTitle(m.title);
      if (n.length >= 5 &&
          berbatTitles.any((bt) => n.startsWith(bt) || bt.startsWith(n))) {
        continue;
      }

      if (seen.add(key)) fresh.add(m);
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

      // Soft filter: Eh (1) oylanan filmin recommendations/similar havuzunda olanlara puan cezası (-0.25)
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
      double penalty = 0.0;
      if (ehKeys.contains(key)) {
        penalty = -0.25;
      }
      // Impression cooldown: yakın zamanda gösterilmişse hafif geri çekil.
      if (cooldownKeys.contains(key)) {
        penalty -= cooldownPenalty;
      }
      // Çoklu tohum kesişimi: 2+ beğeninin benzerlerinde geçen aday öne çıkar.
      final overlap = seedOverlapBoost(seedTitlesByKey[key]?.length ?? 0);

      final raw =
          blend(genreSim: genreSim, voteAverage: m.voteAverage) +
          penalty +
          overlap;
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

        // Soft filter penalty check again in re-rank phase
        final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
        double penalty = 0.0;
        if (ehKeys.contains(key)) {
          penalty = -0.25;
        }
        if (cooldownKeys.contains(key)) {
          penalty -= cooldownPenalty;
        }
        final overlap = seedOverlapBoost(seedTitlesByKey[key]?.length ?? 0);

        final raw =
            blend(
              genreSim: genreSim,
              kwSim: kwSim,
              voteAverage: m.voteAverage,
            ) +
            penalty +
            overlap;
        m.personalizedMatchScore = toDisplayScore(raw);
        top[i].score = raw;
      }
    }

    // Sosyal kanıt: arkadaş sinyali olan adayları yükselt + gerekçele.
    applyFriendSignals(scored, friendSignals);

    // Keşif için jitter (gürültü) ekle (yalnızca swipe kuyruğunda kullanılabilir)
    if (jitter > 0.0) {
      final random = Random();
      for (final s in scored) {
        s.score += (random.nextDouble() * 2 * jitter) - jitter;
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final ordered = diversify ? applyDiversity(scored) : scored;
    var result = ordered.map((s) => s.movie).toList();
    if (suppressFranchises) {
      result = suppressFranchiseDuplicates(result);
    }
    return result;
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
