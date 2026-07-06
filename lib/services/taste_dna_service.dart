import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import '../models/taste_dna.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'tmdb_service.dart';

/// Hesap için sadeleştirilmiş puanlama satırı (saf çekirdeğin girdisi).
typedef DnaRating = ({
  int rating,
  List<int> genreIds,
  int createdAt,
  int? year,
  double popularity,
});

/// "Sinema DNA'sı" — kullanıcının zevkini deterministik, doğru ve spesifik bir
/// kimliğe dönüştürür. Sihirle zırva arasındaki çizgi *spesifiklik*: motor
/// bariz olanı ("aksiyon seviyorsun") değil, veriden çıkan ince gerçeği söyler.
///
/// [compute] tamamen saftır (ağ/DB yok) → birim test edilebilir. [generate]
/// veriyi toplar (puanlamalar + keyword isimleri + telemetri) ve compute'u çağırır.
class TasteDnaService {
  final TmdbService _service;
  TasteDnaService(this._service);

  static const _likedDecay = 0.00385; // ~180 gün yarı ömür (motorla aynı)

  /// Tür → arketip kümesi. En baskın türün kümesi arketipi belirler.
  static const Map<int, String> _genreToCluster = {
    27: 'dark', 53: 'dark', 9648: 'dark', 80: 'dark', // korku/gerilim/gizem/suç
    18: 'emotion', 10749: 'emotion', // dram/romantik
    878: 'world', 14: 'world', 10765: 'world', // bilim kurgu/fantastik
    28: 'adrenaline',
    12: 'adrenaline',
    10759: 'adrenaline',
    10752: 'adrenaline',
    35: 'joy', 10402: 'joy', // komedi/müzik
    99: 'truth', 36: 'truth', // belgesel/tarih
    16: 'child', 10751: 'child', // animasyon/aile
  };

  static const Map<String, String> _clusterToArchetype = {
    'dark': 'dark_chronicler',
    'emotion': 'emotion_seeker',
    'world': 'world_builder',
    'adrenaline': 'adrenaline_junkie',
    'joy': 'joy_chaser',
    'truth': 'truth_seeker',
    'child': 'eternal_child',
  };

  /// Tema olarak gösterilmemesi gereken gürültü keyword'leri.
  static const _themeStoplist = {
    'aftercreditsstinger',
    'duringcreditsstinger',
    'based on novel or book',
    'based on novel',
    'woman director',
    'live action',
    'sequel',
    'remake',
  };

  /// Saf çekirdek: girdilerden DNA üretir. [themes] önceden çözülmüş keyword
  /// isimleridir (ağ gerektirdiğinden [generate]'te toplanır).
  static TasteDna compute({
    required List<DnaRating> ratings,
    required List<String> themes,
    Map<String, List<DnaMovieRef>> themeEvidence = const {},
    required double? accuracy,
    required int accuracySample,
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final total = ratings.where((r) => r.rating >= 0).length;

    // ── Tür ağırlıkları (decay'li) + beğeni/beğenmeme sayacı (kör nokta) ──
    final genreWeight = <int, double>{};
    final genreLiked = <int, int>{};
    final genreDisliked = <int, int>{};
    for (final r in ratings) {
      final days = (now - r.createdAt) / 86400000.0;
      final decay = exp(-_likedDecay * days);
      for (final g in r.genreIds) {
        if (r.rating >= 2) {
          genreWeight[g] =
              (genreWeight[g] ?? 0) + (r.rating == 3 ? 2.0 : 1.0) * decay;
          genreLiked[g] = (genreLiked[g] ?? 0) + 1;
        } else if (r.rating == 0 || r.rating == 1) {
          // Yalnızca gerçek beğenmeme (Berbat/Eh). "İzlemedim" (-1) bir yargı
          // DEĞİLDİR — sayılırsa çok atlanan türler sahte kör nokta üretir.
          genreDisliked[g] = (genreDisliked[g] ?? 0) + 1;
        }
      }
    }
    final topGenres =
        (genreWeight.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => e.key)
            .take(3)
            .toList();

    // Kör nokta: en az 3 kez karşılaşılıp beğenilme oranı en düşük tür.
    int? blindSpot;
    double worstRatio = 1.0;
    final allGenres = {...genreLiked.keys, ...genreDisliked.keys};
    for (final g in allGenres) {
      final liked = genreLiked[g] ?? 0;
      final disliked = genreDisliked[g] ?? 0;
      final seen = liked + disliked;
      if (seen < 3) continue;
      final ratio = liked / seen;
      if (ratio < 0.34 && ratio < worstRatio) {
        worstRatio = ratio;
        blindSpot = g;
      }
    }

    // ── Çağ imzası ──
    final likedYears = ratings
        .where((r) => r.rating >= 2 && r.year != null)
        .map((r) => r.year!)
        .toList();
    double modernShare = 0;
    String? eraKey;
    if (likedYears.length >= 3) {
      modernShare =
          likedYears.where((y) => y >= 2015).length / likedYears.length;
      final classicShare =
          likedYears.where((y) => y < 2000).length / likedYears.length;
      if (modernShare >= 0.6) {
        eraKey = 'modern';
      } else if (classicShare >= 0.4) {
        eraKey = 'classic_soul';
      } else {
        eraKey = 'time_traveler';
      }
    }

    // ── Derinlik (popülerlik ekseni) ──
    final likedPop = ratings
        .where((r) => r.rating >= 2)
        .map((r) => r.popularity)
        .toList();
    String? depthKey;
    if (likedPop.length >= 4) {
      final obscure = likedPop.where((p) => p < 30).length / likedPop.length;
      final mainstream =
          likedPop.where((p) => p > 120).length / likedPop.length;
      if (obscure >= 0.5) {
        depthKey = 'deep_digger';
      } else if (mainstream >= 0.5) {
        depthKey = 'zeitgeist';
      } else {
        depthKey = 'balanced';
      }
    }

    // ── Eleştirmen profili ──
    final harika = ratings.where((r) => r.rating == 3).length;
    final harikaShare = total > 0 ? harika / total : 0.0;
    String? criticKey;
    if (total >= 8) {
      if (harikaShare <= 0.15) {
        criticKey = 'tough';
      } else if (harikaShare >= 0.5) {
        criticKey = 'generous';
      } else {
        criticKey = 'balanced';
      }
    }

    // ── Zevk kayması (eski yarı vs yeni yarı, beğeniler) ──
    int? shiftFrom;
    int? shiftTo;
    final liked = ratings.where((r) => r.rating >= 2).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (liked.length >= 8) {
      final mid = liked.length ~/ 2;
      final older = liked.sublist(0, mid);
      final newer = liked.sublist(mid);
      final oldTop = _dominantGenre(older);
      final newTop = _dominantGenre(newer);
      if (oldTop != null && newTop != null && oldTop != newTop) {
        shiftFrom = oldTop;
        shiftTo = newTop;
      }
    }

    // ── Arketip (Cluster-based blending) ──
    String archetype = 'genre_nomad';
    String? secondaryArchetype;

    final clusterWeights = <String, double>{};
    genreWeight.forEach((g, w) {
      final cluster = _genreToCluster[g];
      if (cluster != null) {
        clusterWeights[cluster] = (clusterWeights[cluster] ?? 0.0) + w;
      }
    });

    final sortedClusters = (clusterWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)));

    if (sortedClusters.isNotEmpty) {
      final topCluster = sortedClusters.first.key;
      archetype = _clusterToArchetype[topCluster] ?? 'genre_nomad';

      if (sortedClusters.length >= 2) {
        final secondCluster = sortedClusters[1].key;
        final secondWeight = sortedClusters[1].value;
        final topWeight = sortedClusters.first.value;

        if (secondWeight >= 1.5 && secondWeight >= topWeight * 0.40) {
          secondaryArchetype = _clusterToArchetype[secondCluster];
        }
      }
    }

    return TasteDna(
      archetypeKey: archetype,
      secondaryArchetypeKey: secondaryArchetype,
      topGenres: topGenres,
      blindSpotGenre: blindSpot,
      themes: themes.take(5).toList(),
      themeEvidence: themeEvidence,
      eraKey: eraKey,
      modernShare: modernShare,
      depthKey: depthKey,
      criticKey: criticKey,
      harikaShare: harikaShare,
      shiftFromGenre: shiftFrom,
      shiftToGenre: shiftTo,
      accuracy: accuracySample >= 8 ? accuracy : null,
      accuracySample: accuracySample,
      totalRated: total,
      generatedAt: now,
    );
  }

  static int? _dominantGenre(List<DnaRating> rows) {
    final counts = <int, int>{};
    for (final r in rows) {
      for (final g in r.genreIds) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  /// Veriyi toplar (puanlamalar + keyword isimleri + telemetri) ve DNA üretir.
  Future<TasteDna> generate({String? userId}) async {
    final raw = await DatabaseHelper().getRatings();

    final telemetry = await PrefsService.getRecoTelemetry();
    var shown = 0;
    var likedCount = 0;
    for (final bucket in telemetry.values) {
      shown += bucket['shown'] ?? 0;
      likedCount += bucket['liked'] ?? 0;
    }
    final accuracy = shown > 0 ? likedCount / shown : null;

    // Hash check
    final ratingCount = raw.length;
    final maxUpdatedAt = raw.fold<int>(
      0,
      (maxVal, r) => max(
        maxVal,
        (r['updated_at'] as int? ?? r['created_at'] as int? ?? 0),
      ),
    );
    final inputHash = "$ratingCount|$maxUpdatedAt|${userId ?? ''}|$shown";

    final cachedData = await PrefsService.getCachedDna();
    if (cachedData != null && cachedData['hash'] == inputHash) {
      try {
        final decoded = jsonDecode(cachedData['json']!);
        if (decoded is Map<String, dynamic>) {
          debugPrint("DNA cache hit! Skipping generation.");
          return TasteDna.fromJson(decoded);
        }
      } catch (e) {
        debugPrint("Failed to parse cached DNA JSON: $e");
      }
    }

    final ratings = <DnaRating>[];
    for (final r in raw) {
      final movie = r['movie'];
      int? year;
      double pop = 0.0;
      if (movie != null) {
        final yrStr = (movie as dynamic).year as String? ?? '';
        year = int.tryParse(yrStr);
        pop = ((movie as dynamic).popularity as num?)?.toDouble() ?? 0.0;
      } else {
        final relDate =
            r['release_date'] as String? ??
            r['movie']?['releaseDate'] as String?;
        if (relDate != null && relDate.length >= 4) {
          year = int.tryParse(relDate.substring(0, 4));
        }
        pop = (r['popularity'] as num?)?.toDouble() ?? 0.0;
      }
      ratings.add((
        rating: r['rating'] as int,
        genreIds:
            (r['genreIds'] as List?)?.whereType<int>().toList() ?? const [],
        createdAt: r['created_at'] as int,
        year: year,
        popularity: pop,
      ));
    }

    final themeResult = await _aggregateThemes(raw);

    final dna = compute(
      ratings: ratings,
      themes: themeResult.themes,
      themeEvidence: themeResult.evidence,
      accuracy: accuracy,
      accuracySample: shown,
    );

    // Cache the result
    try {
      await PrefsService.cacheDna(jsonEncode(dna.toJson()), inputHash);
    } catch (e) {
      debugPrint("Failed to save DNA to cache: $e");
    }

    return dna;
  }

  /// En yeni beğenilerin keyword isimlerini frekansa göre toplar; gürültü
  /// keyword'leri elenir, en güçlü 5 tema döner. Keyword uçları cache'li.
  Future<({List<String> themes, Map<String, List<DnaMovieRef>> evidence})>
  _aggregateThemes(List<Map<String, dynamic>> rawRatings) async {
    try {
      final liked = rawRatings.where((r) => (r['rating'] as int) >= 2).toList()
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        );

      // Adaptif seed: Beğeni sayısına göre 8 ile 20 arası.
      final seedCount = (liked.length <= 8)
          ? 8
          : (liked.length >= 20 ? 20 : liked.length);
      final seeds = liked.take(seedCount).toList();
      if (seeds.isEmpty)
        return (
          themes: const <String>[],
          evidence: const <String, List<DnaMovieRef>>{},
        );

      final lists = await Future.wait(
        seeds.map((r) {
          final id = r['id'] as int;
          final isTV = r['isTV'] as bool? ?? false;
          return _service
              .getKeywords(id, isTV: isTV)
              .catchError((_) => <String>[]);
        }),
      );

      final counts = <String, int>{};
      final themeToMovies = <String, List<DnaMovieRef>>{};

      for (var i = 0; i < seeds.length; i++) {
        final r = seeds[i];
        final kws = lists[i];
        final movie = r['movie'] as Movie?;
        final DnaMovieRef ref;
        if (movie != null) {
          ref = DnaMovieRef(
            id: movie.id,
            title: movie.title,
            posterPath: movie.posterPath,
            isTV: movie.isTV,
          );
        } else {
          final id = r['id'] as int? ?? r['movie_id'] as int? ?? 0;
          final title = r['title'] as String? ?? '';
          final posterPath = r['poster_path'] as String?;
          final isTV = r['isTV'] as bool? ?? ((r['is_tv'] as int?) == 1);
          if (id == 0 || title.isEmpty) continue;
          ref = DnaMovieRef(
            id: id,
            title: title,
            posterPath: posterPath,
            isTV: isTV,
          );
        }

        for (final raw in kws) {
          final name = raw.toLowerCase().trim();
          if (name.isEmpty || _themeStoplist.contains(name)) continue;
          counts[name] = (counts[name] ?? 0) + 1;

          final list = themeToMovies[name] ??= [];
          if (!list.any((m) => m.id == ref.id && m.isTV == ref.isTV)) {
            list.add(ref);
          }
        }
      }

      // En az 2 yapımda geçen temalar öne çıkar (tek seferlik gürültü elenir);
      // hiç tekrar eden yoksa en sık tekillere düşülür.
      var ranked = counts.entries.where((e) => e.value >= 2).toList();
      if (ranked.isEmpty) ranked = counts.entries.toList();
      ranked.sort((a, b) => b.value.compareTo(a.value));

      final topThemes = ranked.take(5).map((e) => e.key).toList();
      final evidence = <String, List<DnaMovieRef>>{};
      for (final t in topThemes) {
        evidence[t] = (themeToMovies[t] ?? []).take(3).toList();
      }

      return (themes: topThemes, evidence: evidence);
    } catch (e, st) {
      debugPrint("Theme aggregation failed: $e\n$st");
      return (
        themes: const <String>[],
        evidence: const <String, List<DnaMovieRef>>{},
      );
    }
  }
}
