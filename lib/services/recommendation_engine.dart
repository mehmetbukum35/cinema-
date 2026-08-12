import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import '../models/cultural_preferences.dart';
import '../models/discovery_context.dart';
import 'cultural_classifier.dart';
import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/library_facade.dart';
import 'prefs/taste_prefs.dart';
import 'recommendation_experiment_service.dart';
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
///  2. Ön eleme: ucuz bir tür+puan skoruyla keyword'ü çekilecek adaylar
///     SEÇİLİR (sıralanmaz) — keyword uçları başlık başına bir TMDB isteği.
///  3. Tek puanlama: herkes aynı formülle puanlanır; keyword'ü çekilmeyen
///     aday çekilenlerin ORTALAMASINI alır, böylece "cache'te olmak" bir
///     sıralama sinyaline dönüşmez.
///  4. Çeşitlilik (MMR-lite): birbirinin kopyası türdeki adaylar cezalandırılır
///     ki ray tek tip görünmesin.
///  5. Gerekçe atıfı: her adaya "neden önerildi" etiketi (seed adı / arkadaş
///     adı) yazılır — UI'daki "seni tanıyor" hissinin taşıyıcısı.
class RecommendationEngine {
  final TmdbService _service;

  /// Aktif arayüz dili. Kültürel "ev bölgesi" çözümü buna bakar; kullanıcı
  /// dili değiştirdiğinde sonraki sıralama yeni dile göre yapılır.
  final String Function() localeCode;

  RecommendationEngine(this._service, {String Function()? localeCode})
    : localeCode = localeCode ?? _defaultLocaleCode;

  static String _defaultLocaleCode() => 'tr';

  /// Kullanıcının anahtar kelime zevk vektörü (keyword_id → ağırlık).
  Map<int, double>? _userKeywordVector;

  /// Vektördeki keyword'lerin okunabilir adları (keyword_id → ad).
  /// Gerekçe etiketi için: "'zaman yolculuğu' temasını sevdiğin için".
  /// Vektörle birlikte, aynı ağ yanıtından doldurulur.
  Map<int, String>? _keywordNames;

  /// Kullanıcı oylama listesinin bellek önbelleği.
  List<Map<String, dynamic>>? _cachedRatings;

  /// Beğenilmeyen (Eh/Berbat) filmlerin benzer/öneri anahtar kelime önbelleği.
  (Set<String> berbatKeys, Set<String> ehKeys)? _cachedNegativeKeys;

  /// Zevk profili değişti veya senkronizasyon yapıldı — önbelleği temizle.
  ///
  /// DNA cache'i BİLEREK silinmez: TasteDnaService.generate kendi girdi
  /// hash'iyle (puan sayısı + son updated_at + telemetri) tazeliği zaten
  /// doğruluyor. Burada silmek, her sync'te DNA'nın yeniden üretilmesine ve
  /// yayın imleci (last_published_dna_hash) kaybolduğu için veri değişmemiş
  /// olsa bile sunucuya yeniden POST /social/dna atılmasına yol açıyordu.
  Future<void> invalidateCache({bool isNegativeChange = true}) async {
    _userKeywordVector = null;
    _keywordNames = null;
    _cachedRatings = null;
    if (isNegativeChange) {
      _cachedNegativeKeys = null;
    }
  }

  /// Oylamaları bellekten veya veritabanından çeken yardımcı metot.
  /// Gizli puanlar reco sinyallerine (keyword / negatif seed / cultural boost)
  /// sızmasın — [getRatingsForWeights] ile aynı kural.
  Future<List<Map<String, dynamic>>> _getRatings() async {
    final cached = _cachedRatings;
    if (cached != null) return cached;
    final ratings = await DatabaseHelper().getRatings();
    final public = ratings
        .where((r) => (r['is_private'] as int? ?? 0) != 1)
        .toList(growable: false);
    _cachedRatings = public;
    return public;
  }

  /// Ham skor harmanı. [kwSim] null ise keyword fazı atlanır.
  ///
  /// Ağırlıkların tek doğruluk kaynağı [RecommendationExperimentService.active].
  /// (Burada vaktiyle bir kopyaları duruyordu; hiçbir yerden okunmuyor ama
  /// "tek doğruluk kaynağı" diye etiketli oldukları için yanıltıcıydılar.)
  static double blend({
    required double genreSim,
    double? kwSim,
    required double voteAverage,
    RecommendationExperiment experiment =
        RecommendationExperimentService.active,
  }) {
    final vote = voteAverage / 10.0;
    if (kwSim == null) {
      return experiment.genreOnlyWeights.genre * genreSim +
          experiment.genreOnlyWeights.vote * vote;
    }
    return experiment.fullWeights.genre * genreSim +
        experiment.fullWeights.keyword * kwSim +
        experiment.fullWeights.vote * vote;
  }

  /// Ham skoru kullanıcıya gösterilen uyum yüzdesine [40, 98] eşler.
  /// Sigmoid 0.2 (cold-start ortalaması) merkezlidir; 98 tavanı "sahte %100"
  /// vaadini engeller.
  static int toDisplayScore(double raw) {
    final z = (raw - 0.2) * 4.0;
    final sigmoid = 1.0 / (1.0 + exp(-z));
    return (40 + (sigmoid * 58)).round().clamp(40, 98);
  }

  static double culturalPreferenceInfluence(int ratingCount) {
    if (ratingCount < 10) return 1.0;
    if (ratingCount < 25) return 0.6;
    if (ratingCount < 50) return 0.3;
    return 0.15;
  }

  static double culturalBoost({
    required Movie movie,
    required CulturalPreferences preferences,
    required int ratingCount,
  }) {
    final cultures = CulturalClassifier.classify(movie);
    if (cultures.isEmpty || preferences.isEmpty) return 0;
    // Ortak yapımlarda prefer, avoid'u yener (abs-max cezası yok).
    var preferBoost = 0.0;
    var exploreBoost = 0.0;
    var avoidBoost = 0.0;
    for (final culture in cultures) {
      switch (preferences.levelFor(culture)) {
        case CulturePreferenceLevel.prefer:
          if (preferBoost < 0.10) preferBoost = 0.10;
        case CulturePreferenceLevel.explore:
          if (exploreBoost < 0.04) exploreBoost = 0.04;
        case CulturePreferenceLevel.avoid:
          if (avoidBoost > -0.12) avoidBoost = -0.12;
        case CulturePreferenceLevel.neutral:
          break;
      }
    }
    final strongest = preferBoost > 0
        ? preferBoost
        : (avoidBoost < 0 ? avoidBoost : exploreBoost);
    return strongest * culturalPreferenceInfluence(ratingCount);
  }

  /// Kullanıcının "yerli" sinema çerçevesi.
  ///
  /// 1) `prefer` ettiği kültürler (açık tercih en güçlü sinyal)
  /// 2) yoksa uygulama dili → varsayılan bölge (`tr`→Türk, `en`→Hollywood)
  static Set<String> resolveHomeCultures({
    required CulturalPreferences preferences,
    String languageCode = 'tr',
  }) {
    final preferred = preferences.levels.entries
        .where((e) => e.value == CulturePreferenceLevel.prefer)
        .map((e) => e.key)
        .toSet();
    if (preferred.isNotEmpty) return preferred;

    return switch (languageCode.toLowerCase()) {
      'tr' => const {'turkish'},
      'en' => const {'hollywood'},
      _ => const {'hollywood'},
    };
  }

  /// Kültür etiketlerini (turkish, iranian, european vb.) TMDB discover sorgu
  /// parametrelerine (originCountry, originalLanguage) dönüştürür.
  static List<({String? originCountry, String? originalLanguage})>
  cultureToTmdbFilters(Set<String> homeCultures) {
    final filters = <({String? originCountry, String? originalLanguage})>[];
    for (final c in homeCultures) {
      switch (c) {
        case 'turkish':
          filters.add((originCountry: 'TR', originalLanguage: 'tr'));
        case 'iranian':
          filters.add((originCountry: 'IR', originalLanguage: 'fa'));
        case 'korean':
          filters.add((originCountry: 'KR', originalLanguage: 'ko'));
        case 'japanese':
          filters.add((originCountry: 'JP', originalLanguage: 'ja'));
        case 'indian':
          filters.add((originCountry: 'IN', originalLanguage: null));
        case 'european':
          filters.add((
            originCountry: 'FR|DE|ES|IT|GB|SE|NL|DK|NO|FI|AT|PL|CZ',
            originalLanguage: null,
          ));
        case 'latin_american':
          filters.add((
            originCountry: 'MX|BR|AR|CL|CO|PE|CU',
            originalLanguage: null,
          ));
        case 'east_asian':
          filters.add((originCountry: 'CN|HK|TW', originalLanguage: null));
        case 'hollywood':
          filters.add((originCountry: 'US|CA|AU|NZ', originalLanguage: 'en'));
        default:
          break;
      }
    }
    return filters;
  }

  static bool matchesDiscoveryContext(
    Movie movie,
    DiscoveryContext context, {
    Set<String> homeCultures = const {'turkish'},
  }) {
    if (context.media == DiscoveryMedia.movie && movie.isTV) return false;
    if (context.media == DiscoveryMedia.tv && !movie.isTV) return false;
    if (context.origin == DiscoveryOrigin.any) return true;

    final cultures = CulturalClassifier.classify(movie);
    final isHome =
        homeCultures.isNotEmpty && cultures.any(homeCultures.contains);

    if (context.origin == DiscoveryOrigin.local) {
      return isHome;
    }
    // Yabancı: ev çerçevesiyle kesişmeyen (sınıflanamayanlar da yabancı sayılır —
    // aksi halde keşif boşalır).
    if (context.origin == DiscoveryOrigin.foreign) {
      return !isHome;
    }
    return true;
  }

  static double discoveryContextBoost(Movie movie, DiscoveryContext context) {
    var boost = 0.0;
    final runtime = movie.runtimeMinutes;
    if (runtime != null && context.duration != DiscoveryDuration.any) {
      final shortLimit = movie.isTV ? 40 : 100;
      final longLimit = movie.isTV ? 60 : 140;
      final matches = switch (context.duration) {
        DiscoveryDuration.short => runtime <= shortLimit,
        DiscoveryDuration.medium => runtime > shortLimit && runtime < longLimit,
        DiscoveryDuration.long => runtime >= longLimit,
        DiscoveryDuration.any => true,
      };
      boost += matches ? 0.08 : -0.10;
    }
    switch (context.familiarity) {
      case DiscoveryFamiliarity.safe:
        boost += (movie.voteAverage / 10.0) * 0.05;
        if (movie.voteCount >= 1000) boost += 0.03;
      case DiscoveryFamiliarity.surprise:
        if (movie.popularity < 40) boost += 0.07;
        if (movie.voteCount < 1000) boost += 0.03;
      case DiscoveryFamiliarity.balanced:
        break;
    }
    return boost;
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
    final names = <int, String>{};
    try {
      final ratings = await _getRatings();
      // En son 15 oylamayı al (tüm beğenilenler ve beğenilmeyenler dahil)
      final sortedRatings = ratings.toList()
        ..sort(
          (a, b) => (int.tryParse(b['created_at']?.toString() ?? '') ?? 0)
              .compareTo(int.tryParse(a['created_at']?.toString() ?? '') ?? 0),
        );
      final seeds = sortedRatings.take(15).toList();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final kwLists = await Future.wait(
        seeds.map((r) {
          final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
          final isTV =
              r['isTV'] == true ||
              r['is_tv'] == 1 ||
              r['is_tv']?.toString() == '1';
          // Entries (id+ad) çekiyoruz: adlar gerekçe etiketi için lazım ve
          // getKeywordIds ile AYNI önbellek girdisinden geliyor — ek istek yok.
          return _service
              .getKeywordEntries(id, isTV: isTV)
              .catchError((_) => const <({int id, String name})>[]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final r = seeds[i];
        final rating = int.tryParse(r['rating']?.toString() ?? '') ?? -1;
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

        final createdAt = int.tryParse(r['created_at']?.toString() ?? '') ?? 0;
        final days = (nowMs - createdAt) / 86400000.0;
        final decay = exp(-0.00385 * days);
        final w = base * decay;
        for (final entry in kwLists[i]) {
          vec[entry.id] = (vec[entry.id] ?? 0.0) + w;
          names[entry.id] = entry.name;
        }
      }

      // Favoriler: kalıcı ÇEKİRDEK zevk. Oylar kısa vadeli mod katar; Top 20
      // ise "hayatımın yapımları" — decaysiz, rank-ağırlıklı olarak keyword
      // vektörüne eklenir. Tema/keyword benzerliği "seni tanıyorum" hissinin asıl
      // taşıyıcısı olduğundan (bkz. similarityScore), favorilerin buraya girmesi
      // ince re-rank'ı gerçekten kişiselleştirir.
      try {
        final db = DatabaseHelper();
        final favMovies = await db
            .getFavorites(false)
            .catchError((_) => <Movie>[]);
        final favShows = await db
            .getFavorites(true)
            .catchError((_) => <Movie>[]);
        final favEntries = <({int id, bool isTV, double w})>[];
        void collect(List<Movie> favs) {
          for (var i = 0; i < favs.length; i++) {
            // getFavorites rank sırasında döner → liste indeksi = sıra.
            favEntries.add((
              id: favs[i].id,
              isTV: favs[i].isTV,
              w: 1.5 * PrefsLibraryFacade.favoriteRankWeight(i),
            ));
          }
        }

        collect(favMovies);
        collect(favShows);
        favEntries.sort((a, b) => b.w.compareTo(a.w));
        final topFav = favEntries.take(10).toList();
        if (topFav.isNotEmpty) {
          final favKwLists = await Future.wait(
            topFav.map(
              (f) => _service
                  .getKeywordEntries(f.id, isTV: f.isTV)
                  .catchError((_) => const <({int id, String name})>[]),
            ),
          );
          for (var i = 0; i < topFav.length; i++) {
            for (final entry in favKwLists[i]) {
              vec[entry.id] = (vec[entry.id] ?? 0.0) + topFav[i].w;
              names[entry.id] = entry.name;
            }
          }
        }
      } catch (e) {
        debugPrint("Favorite keyword seeding failed: $e");
      }
    } catch (e, st) {
      debugPrint("Error calculating keyword vector: $e\n$st");
      // Hata → boş vektör; keyword fazı sessizce atlanır (cold-start gibi).
    }

    _userKeywordVector = vec;
    _keywordNames = names;
    return vec;
  }

  /// [movieKeywordIds] içinde kullanıcının EN ÇOK sevdiği temanın adı.
  /// Gerekçe etiketi için; eşleşme yoksa null (rozet gerekçesiz gösterilir).
  String? _bestKeywordName(List<int> movieKeywordIds, Map<int, double> vector) {
    final names = _keywordNames;
    if (names == null) return null;
    int? bestId;
    var bestWeight = 0.0;
    for (final id in movieKeywordIds) {
      final w = vector[id] ?? 0.0;
      if (w > bestWeight && names.containsKey(id)) {
        bestWeight = w;
        bestId = id;
      }
    }
    return bestId == null ? null : names[bestId];
  }

  /// Kullanıcının tepe temalarından aday toplar (`with_keywords` discover).
  ///
  /// Tür-bazlı discover ve tohum listeleri, temaya uyan ama TÜRÜ profile
  /// uymayan yapımı hiç getirmiyor: zihinsel bilimkurguyu seven birine aynı
  /// temayı işleyen bir dram, Drama ağırlığı düşük olduğu için ne discover'dan
  /// ne tohumlardan geliyor. Bu metot o boşluğu en fazla 2 istekle kapatır.
  ///
  /// Soğuk başlangıçta (boş vektör) hiç istek yapmadan boş liste döner.
  Future<List<Movie>> fetchKeywordCandidates({
    DiscoveryContext discoveryContext = const DiscoveryContext(),
    int keywordCount = 5,
    int page = 1,
  }) async {
    try {
      final vector = await buildUserKeywordVector();
      final positive = vector.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (positive.isEmpty) return const [];

      final ids = positive.take(keywordCount).map((e) => e.key).toList();
      final results = await _service.discover(
        // `|` = OR: temalardan herhangi biri yeterli.
        keywordStr: ids.join('|'),
        includeMovies: discoveryContext.media != DiscoveryMedia.tv,
        includeTv: discoveryContext.media != DiscoveryMedia.movie,
        page: page,
      );

      for (final m in results) {
        m
          ..recoSource = 'keyword'
          ..recoReasonType = 'keyword';
      }
      return results;
    } catch (e) {
      debugPrint('Keyword candidate fetch failed: $e');
      return const [];
    }
  }

  /// İki rank-sıralı listeyi harmanlar: a[0], b[0], a[1], b[1], … Böylece film ve
  /// dizi favorilerinin üst sıraları öne geçer (tek tür tohum havuzunu ele geçirmez).
  static List<Movie> _interleaveByRank(List<Movie> a, List<Movie> b) {
    final out = <Movie>[];
    final n = max(a.length, b.length);
    for (var i = 0; i < n; i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }

  /// Son [seedCount] tohum yapımı (öncelik sırasıyla Favoriler + Harika(3) -> İyi(2) -> Watchlist)
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
        final telemetry = await PrefsTastePrefs.getRecoTelemetry();
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
      final harikaSeeds =
          ratings
              .where(
                (r) => (int.tryParse(r['rating']?.toString() ?? '') ?? -1) == 3,
              )
              .toList()
            ..sort(
              (a, b) => (int.tryParse(b['created_at']?.toString() ?? '') ?? 0)
                  .compareTo(
                    int.tryParse(a['created_at']?.toString() ?? '') ?? 0,
                  ),
            );
      final iyiSeeds =
          ratings
              .where(
                (r) => (int.tryParse(r['rating']?.toString() ?? '') ?? -1) == 2,
              )
              .toList()
            ..sort(
              (a, b) => (int.tryParse(b['created_at']?.toString() ?? '') ?? 0)
                  .compareTo(
                    int.tryParse(a['created_at']?.toString() ?? '') ?? 0,
                  ),
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

      // Favoriler (Top 20) rank sırasıyla, film/dizi harmanlı — cold-start yedeği
      // DEĞİL, birinci sınıf tohum. En sevdiklerin keşif havuzunu her zaman besler
      // ("X'i favorine aldığın için" gerekçesiyle).
      final favMovies = await db
          .getFavorites(false)
          .catchError((_) => <Movie>[]);
      final favShows = await db.getFavorites(true).catchError((_) => <Movie>[]);
      final rankedFavs = _interleaveByRank(favMovies, favShows);

      // finalSeedCount'un ~1/3'ü üst-sıra favorilere ayrılır; hiç oy yoksa hepsi.
      final favReserve = ratingSeeds.isEmpty
          ? finalSeedCount
          : max(1, (finalSeedCount / 3).round());
      for (final m in rankedFavs.take(favReserve)) {
        if (seedItems.length >= finalSeedCount) break;
        seedItems.add((id: m.id, isTV: m.isTV, title: m.title));
      }

      // 1. Kalan slotlar: en son beğenilen (Harika/İyi) oylar.
      for (final r in ratingSeeds) {
        if (seedItems.length >= finalSeedCount) break;
        final movie = r['movie'] as Movie?;
        if (movie != null &&
            !seedItems.any((s) => s.id == movie.id && s.isTV == movie.isTV)) {
          seedItems.add((id: movie.id, isTV: movie.isTV, title: movie.title));
        }
      }

      // 2. Hâlâ eksikse kalan favorilerle doldur.
      if (seedItems.length < finalSeedCount) {
        for (final m in rankedFavs) {
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
      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
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
            final rating = int.tryParse(r['rating']?.toString() ?? '') ?? -1;
            return rating == 0 || rating == 1;
          }).toList()..sort(
            (a, b) => (int.tryParse(b['created_at']?.toString() ?? '') ?? 0)
                .compareTo(
                  int.tryParse(a['created_at']?.toString() ?? '') ?? 0,
                ),
          );
      final seeds = disliked.take(3).toList();
      if (seeds.isEmpty) {
        _cachedNegativeKeys = (berbatKeys, ehKeys);
        return _cachedNegativeKeys!;
      }

      final results = await Future.wait(
        seeds.map((s) {
          final id = int.tryParse(s['id']?.toString() ?? '') ?? 0;
          final isTV =
              s['isTV'] == true ||
              s['is_tv'] == 1 ||
              s['is_tv']?.toString() == '1';
          return Future.wait([
            _service
                .getRecommendations(id, isTV: isTV)
                .catchError((_) => <Movie>[]),
            _service.getSimilar(id, isTV: isTV).catchError((_) => <Movie>[]),
          ]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final rating = int.tryParse(seeds[i]['rating']?.toString() ?? '') ?? -1;
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
  /// [excludedKeys] ile ayıklanır, ucuz bir ön elemeyle [keywordFetchK] adayın
  /// keyword'ü çekilir, herkes TEK formülle puanlanır, arkadaş sinyalleri
  /// eklenir ve çeşitlilik geçişi uygulanır. Dönen listedeki her filmde
  /// `personalizedMatchScore` (ve varsa `recoReason`) doldurulmuş olur.
  ///
  /// [keywordFetchK]: keyword'ü çekilecek aday sayısı. Keyword uçları başlık
  /// başına bir TMDB isteği olduğundan havuzun tamamı çekilemez; çekilmeyen
  /// adaylar çekilenlerin ORTALAMASINI alır (sıfır değil — bkz. puanlama
  /// bloğundaki gerekçe).
  /// [keywordSourceSlots]: `recoSource == 'keyword'` olan adaylara ayrılan
  /// garanti çekim slotu. Bu adaylar tür bakımından zayıf olduğu için ön
  /// elemede dibe düşer; slot olmazsa keyword recall'ı ranking aşamasında
  /// yutulur.
  /// [cooldownKeys]: yakın zamanda kullanıcıya GÖSTERİLMİŞ yapımların
  /// anahtarları — küçük bir skor cezası ([cooldownPenalty]) alır ki vitrin ve
  /// ray her açılışta aynı yüzlerle dizilmesin (impression cooldown).
  Future<List<Movie>> rankForYou(
    List<Movie> candidates, {
    DiscoveryContext discoveryContext = const DiscoveryContext(),
    Set<String> excludedKeys = const {},
    Map<String, List<String>> friendSignals = const {},
    Set<String> cooldownKeys = const {},
    double cooldownPenalty = 0.08,
    int keywordFetchK = 30,
    int keywordSourceSlots = 10,
    bool diversify = true,
    double jitter = 0.0,
    bool suppressFranchises = false,
  }) async {
    // Negatif sinyalleri yükle (similar / recommendations)
    final (berbatKeys, ehKeys) = await fetchNegativeSeedKeys();

    // Berbat (0) oylanan filmlerin franchise/seri isimlerini yükle (Prefix bastırma için)
    final ratings = await _getRatings();
    final berbatTitles = ratings
        .where((r) => (int.tryParse(r['rating']?.toString() ?? '') ?? -1) == 0)
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
    final culturalPreferences = await CulturalPreferenceService.load();
    final homeCultures = resolveHomeCultures(
      preferences: culturalPreferences,
      languageCode: localeCode(),
    );
    final seen = <String>{};
    final fresh = <Movie>[];
    for (final m in candidates) {
      if (!matchesDiscoveryContext(
        m,
        discoveryContext,
        homeCultures: homeCultures,
      )) {
        continue;
      }
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

    final userWeights = await PrefsTastePrefs.getGenreWeights();
    final experiment = RecommendationExperimentService.active;
    final ratingCount = ratings.length;

    String keyOf(Movie m) => "${m.isTV ? 'tv' : 'movie'}_${m.id}";

    // Tür benzerliği hem ön elemede hem nihai puanlamada lazım — bir kez hesapla.
    final genreSims = {
      for (final m in fresh)
        keyOf(m): PrefsTastePrefs.calculateSimilarity(userWeights, m.genreIds),
    };

    // ── 1. Ön eleme: kimin keyword'ü çekilecek? ───────────────────────────
    // Bu skor SIRALAMA DEĞİL SEÇİM içindir. Keyword uçları başlık başına bir
    // TMDB isteği olduğundan hepsini çekemeyiz; nihai puanlama aşağıda tek
    // formülle bir kez yapılır.
    final kwVector = await buildUserKeywordVector();
    final kwSims = <String, double>{};
    if (kwVector.isNotEmpty) {
      final preScores = {
        for (final m in fresh)
          keyOf(m): blend(
            genreSim: genreSims[keyOf(m)]!,
            voteAverage: m.voteAverage,
            experiment: experiment,
          ),
      };
      final preRanked = List.of(fresh)
        ..sort((a, b) => preScores[keyOf(b)]!.compareTo(preScores[keyOf(a)]!));

      final fetchSet = <String, Movie>{
        for (final m in preRanked.take(keywordFetchK)) keyOf(m): m,
        // Keyword discover'dan gelen aday tür bakımından zayıf olduğu için ön
        // elemede dibe düşebilir. Garanti slot olmazsa keyword'ü hiç çekilmez,
        // ortalamaya sabitlenir ve hiç yükselemez — yani recall düzeltmesi
        // ranking aşamasında sessizce yutulur.
        for (final m
            in fresh
                .where((m) => m.recoSource == 'keyword')
                .take(keywordSourceSlots))
          keyOf(m): m,
      };

      final entries = fetchSet.entries.toList(growable: false);
      final kwLists = await Future.wait(
        entries.map(
          (e) => _service
              .getKeywordIds(e.value.id, isTV: e.value.isTV)
              .catchError((_) => <int>[]),
        ),
      );
      for (var i = 0; i < entries.length; i++) {
        final movie = entries[i].value;
        kwSims[entries[i].key] = PrefsTastePrefs.calculateSimilarity(
          kwVector,
          kwLists[i],
        );
        // Gerekçe ancak burada verilebilir: hangi temanın eşleştiğini bilmek
        // için adayın kendi keyword'leri lazım, onlar da bu adımda çekiliyor.
        if (movie.recoSource == 'keyword' && movie.recoReason == null) {
          movie.recoReason = _bestKeywordName(kwLists[i], kwVector);
        }
      }
    }

    // ── 2. Bilinmeyen kwSim'ler ortalamayla atanır ────────────────────────
    // Sıfır atamak "cache'te olmak"ı sıralama sinyaline çevirirdi: keyword'ü
    // bilinen aday pozitif değer alabilirken bilinmeyen tavanı sıfır olan bir
    // cezaya mahkûm olurdu — üstelik cache'te olanlar geçmişte zaten üst
    // sıralara girmiş olanlar, yani kendini pekiştiren bir döngü. Ortalama ile
    // bilgi adayı ortalamaya göre yukarı YA DA aşağı taşır, bilgisizlik nötr
    // kalır. Hiç bilinen yoksa (soğuk başlangıç) keyword fazı tümden atlanır.
    final double? meanKwSim = kwSims.isEmpty
        ? null
        : kwSims.values.reduce((a, b) => a + b) / kwSims.length;

    // ── 3. Tek nihai puanlama ─────────────────────────────────────────────
    // Tek ölçek: eskiden kaba sıralama genreOnlyWeights, re-rank fullWeights
    // kullanıyor ve iki farklı ölçekteki skor birlikte sıralanıyordu. kwSim'i
    // düşük olan her aday sırf ölçek uyuşmazlığından 21+ sıradakilerin altına
    // düşüyordu (başabaş noktası kwSim ~0.52; tipik değer 0.1-0.3).
    final scored = <ScoredMovie>[];
    for (final m in fresh) {
      final key = keyOf(m);
      final genreSim = genreSims[key]!;
      final measuredKwSim = kwSims[key];
      final kwSim = meanKwSim == null ? null : (measuredKwSim ?? meanKwSim);

      // Soft filter: Eh (1) oylanan filmin recommendations/similar havuzunda olanlara puan cezası (-0.25)
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
      final cultureBoost =
          culturalBoost(
            movie: m,
            preferences: culturalPreferences,
            ratingCount: ratingCount,
          ) *
          experiment.preferenceBoostMultiplier;
      final contextBoost =
          discoveryContextBoost(m, discoveryContext) *
          experiment.preferenceBoostMultiplier;

      final raw =
          blend(
            genreSim: genreSim,
            kwSim: kwSim,
            voteAverage: m.voteAverage,
            experiment: experiment,
          ) +
          penalty +
          overlap +
          cultureBoost +
          contextBoost;
      m.recommendationScoreComponents = {
        'genre_similarity': genreSim,
        'keyword_similarity': ?kwSim,
        // Sinyal ölçüldü mü yoksa ortalamayla mı dolduruldu — kalibrasyon
        // analizinin bunu ayırt edebilmesi gerekiyor.
        if (kwSim != null) 'keyword_imputed': measuredKwSim == null ? 1.0 : 0.0,
        'vote_average': m.voteAverage / 10.0,
        'negative_penalty': penalty,
        'seed_overlap': overlap,
        'culture': cultureBoost,
        'context': contextBoost,
        'final': raw,
      };
      m.recommendationModelVersion = experiment.modelVersion;
      if (cultureBoost > 0 && m.recoReason == null) {
        m
          ..recoReason = CulturalClassifier.classify(m).first
          ..recoReasonType = 'culture'
          ..recoSource = 'culture';
      }
      m.personalizedMatchScore = toDisplayScore(raw);
      m.recoSource ??= 'discover';
      scored.add(ScoredMovie(m, raw));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Sosyal kanıt: arkadaş sinyali olan adayları yükselt + gerekçele.
    applyFriendSignals(scored, friendSignals);
    // Görünen uyum %, sıralama skorunun friend-boost sonrası haliyle uyumlu olsun
    // (jitter keşif gürültüsüdür — %'ye yansıtılmaz).
    for (final s in scored) {
      s.movie.personalizedMatchScore = toDisplayScore(s.score);
    }

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
