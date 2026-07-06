import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/taste_dna.dart';
import 'package:ne_izlesem/services/taste_dna_service.dart';

// Sabit "şimdi": decay ve çağ hesapları deterministik olsun.
const _now = 1735689600000; // 2025-01-01 UTC

DnaRating _r({
  required int rating,
  List<int> genres = const [18],
  int daysAgo = 1,
  int? year,
  double popularity = 50,
}) {
  return (
    rating: rating,
    genreIds: genres,
    createdAt: _now - daysAgo * 86400000,
    year: year,
    popularity: popularity,
  );
}

void main() {
  group('TasteDnaService.compute — arketip', () {
    test('baskın karanlık tür → dark_chronicler', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, genres: [27]), // korku
          _r(rating: 3, genres: [53]), // gerilim
          _r(rating: 2, genres: [27, 9648]),
          _r(rating: 2, genres: [80]),
          _r(rating: 1, genres: [35]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.archetypeKey, 'dark_chronicler');
      expect(dna.topGenres.first, anyOf(27, 53));
    });

    test('baskın bilim kurgu/fantastik → world_builder', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, genres: [878]),
          _r(rating: 3, genres: [14]),
          _r(rating: 2, genres: [878]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.archetypeKey, 'world_builder');
    });

    test('beğeni yoksa genre_nomad', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 0, genres: [28]),
          _r(rating: 1, genres: [35]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.archetypeKey, 'genre_nomad');
    });
  });

  group('TasteDnaService.compute — kör nokta', () {
    test('sık karşılaşılıp beğenilmeyen tür kör nokta olur', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 0, genres: [35]), // komedi hep kötü
          _r(rating: 1, genres: [35]),
          _r(rating: 0, genres: [35]),
          _r(rating: 3, genres: [18]),
          _r(rating: 3, genres: [18]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.blindSpotGenre, 35);
    });

    test('yetersiz örneklemde kör nokta yok', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 0, genres: [35]),
          _r(rating: 3, genres: [18]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.blindSpotGenre, isNull);
    });

    test('"İzlemedim" (-1) kaydırmaları kör noktayı ZEHİRLEMEZ', () {
      // Kullanıcı komedileri izlemediği için atlıyor (yargı değil!) ama
      // izlediği tek komediye Harika demiş → komedi kör nokta OLMAMALI.
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: -1, genres: [35]),
          _r(rating: -1, genres: [35]),
          _r(rating: -1, genres: [35]),
          _r(rating: -1, genres: [35]),
          _r(rating: 3, genres: [35]),
          _r(rating: 3, genres: [18]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.blindSpotGenre, isNull);
    });
  });

  group('TasteDnaService.compute — çağ imzası', () {
    test('çoğunluk 2015 sonrası → modern', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, year: 2020),
          _r(rating: 3, year: 2018),
          _r(rating: 2, year: 2022),
          _r(rating: 2, year: 1999),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.eraKey, 'modern');
      expect(dna.modernShare, closeTo(0.75, 1e-9));
    });

    test('eski ağırlıklı → classic_soul', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, year: 1975),
          _r(rating: 3, year: 1988),
          _r(rating: 2, year: 1995),
          _r(rating: 2, year: 2019),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.eraKey, 'classic_soul');
    });
  });

  group('TasteDnaService.compute — eleştirmen profili', () {
    test('nadir Harika → tough', () {
      final ratings = [
        for (var i = 0; i < 9; i++) _r(rating: 1, genres: [18]),
        _r(rating: 3, genres: [18]),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.criticKey, 'tough');
      expect(dna.harikaShare, closeTo(0.1, 1e-9));
    });

    test('bol Harika → generous', () {
      final ratings = [
        for (var i = 0; i < 8; i++) _r(rating: 3, genres: [18]),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.criticKey, 'generous');
    });
  });

  group('TasteDnaService.compute — derinlik', () {
    test('düşük popülerlik → deep_digger', () {
      final ratings = [
        for (var i = 0; i < 5; i++) _r(rating: 3, popularity: 10),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.depthKey, 'deep_digger');
    });

    test('yüksek popülerlik → zeitgeist', () {
      final ratings = [
        for (var i = 0; i < 5; i++) _r(rating: 3, popularity: 300),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.depthKey, 'zeitgeist');
    });
  });

  group('TasteDnaService.compute — zevk kayması', () {
    test('eski yarı vs yeni yarı farklı baskın tür → kayma', () {
      // Eski beğeniler aksiyon (28), yeni beğeniler dram (18).
      final ratings = [
        for (var i = 0; i < 5; i++)
          _r(rating: 3, genres: [28], daysAgo: 300 - i),
        for (var i = 0; i < 5; i++)
          _r(rating: 3, genres: [18], daysAgo: 50 - i),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.shiftFromGenre, 28);
      expect(dna.shiftToGenre, 18);
    });

    test('az veri veya sabit zevkte kayma yok', () {
      final ratings = [
        for (var i = 0; i < 10; i++) _r(rating: 3, genres: [18]),
      ];
      final dna = TasteDnaService.compute(
        ratings: ratings,
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.shiftFromGenre, isNull);
      expect(dna.shiftToGenre, isNull);
    });
  });

  group('TasteDnaService.compute — kanıtlı isabet', () {
    test('yeterli örneklemde oran döner', () {
      final dna = TasteDnaService.compute(
        ratings: [_r(rating: 3)],
        themes: const [],
        accuracy: 0.8,
        accuracySample: 20,
        nowMs: _now,
      );
      expect(dna.accuracy, 0.8);
      expect(dna.accuracySample, 20);
    });

    test('küçük örneklemde isabet gizlenir (null)', () {
      final dna = TasteDnaService.compute(
        ratings: [_r(rating: 3)],
        themes: const [],
        accuracy: 1.0,
        accuracySample: 3,
        nowMs: _now,
      );
      expect(dna.accuracy, isNull);
    });
  });

  group('TasteDnaService.compute — cluster ağırlık harmanlama (arketip)', () {
    test('ikincil arketip tespiti', () {
      // Dark (27, Korku) ağırlığı: 3.0. World (878, Bilim Kurgu) ağırlığı: 2.0.
      // Her ikisi de 1.5 barajını geçer ve oran 2.0 / 3.0 = 66% (> 40% barajı).
      // Dolayısıyla primary = dark_chronicler, secondary = world_builder olmalıdır.
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, genres: [27]), // Korku (+2.0)
          _r(rating: 2, genres: [27]), // Korku (+1.0)
          _r(rating: 3, genres: [878]), // B.Kurgu (+2.0)
          _r(rating: 1, genres: [35]), // Komedi (beğenilmedi, 0)
          _r(rating: 1, genres: [35]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.archetypeKey, 'dark_chronicler');
      expect(dna.secondaryArchetypeKey, 'world_builder');
    });

    test('zayıf ikincil arketip elenir', () {
      // Dark ağırlığı: 3.0. World ağırlığı: 1.0 (baraj altı).
      // Dolayısıyla secondaryArchetypeKey = null olmalıdır.
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, genres: [27]),
          _r(rating: 2, genres: [27]),
          _r(rating: 2, genres: [878]),
          _r(rating: 1, genres: [35]),
          _r(rating: 1, genres: [35]),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.archetypeKey, 'dark_chronicler');
      expect(dna.secondaryArchetypeKey, isNull);
    });
  });

  group('TasteDnaService.compute — yetersiz veri durumunda sinyal gizleme', () {
    test('popülerlik örneklemi < 4 ise depthKey null olur', () {
      final dna = TasteDnaService.compute(
        ratings: [
          _r(rating: 3, popularity: 10),
          _r(rating: 3, popularity: 10),
          _r(rating: 3, popularity: 10),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.depthKey, isNull);
    });

    test('toplam oylama < 8 ise criticKey null olur', () {
      final dna = TasteDnaService.compute(
        ratings: [
          for (var i = 0; i < 7; i++) _r(rating: 3),
        ],
        themes: const [],
        accuracy: null,
        accuracySample: 0,
        nowMs: _now,
      );
      expect(dna.criticKey, isNull);
    });
  });

  group('TasteDna serileştirme', () {
    test('toJson/fromJson round-trip', () {
      final dna = TasteDna(
        archetypeKey: 'dark_chronicler',
        secondaryArchetypeKey: 'world_builder',
        topGenres: const [27, 53],
        blindSpotGenre: 35,
        themes: const ['intikam', 'distopya'],
        themeEvidence: {
          'intikam': [
            DnaMovieRef(id: 101, title: 'Oldboy', posterPath: '/old.jpg', isTV: false),
          ]
        },
        eraKey: 'modern',
        modernShare: 0.75,
        depthKey: 'deep_digger',
        criticKey: 'tough',
        harikaShare: 0.12,
        shiftFromGenre: 28,
        shiftToGenre: 18,
        accuracy: 0.75,
        accuracySample: 12,
        totalRated: 20,
        generatedAt: _now,
      );
      final round = TasteDna.fromJson(dna.toJson());
      expect(round.archetypeKey, dna.archetypeKey);
      expect(round.secondaryArchetypeKey, dna.secondaryArchetypeKey);
      expect(round.topGenres, dna.topGenres);
      expect(round.themes, dna.themes);
      expect(round.themeEvidence['intikam']?.first.title, 'Oldboy');
      expect(round.themeEvidence['intikam']?.first.posterUrl, contains('/old.jpg'));
      expect(round.eraKey, dna.eraKey);
      expect(round.depthKey, dna.depthKey);
      expect(round.criticKey, dna.criticKey);
      expect(round.accuracy, dna.accuracy);
      expect(round.totalRated, dna.totalRated);
      expect(round.isReady, isTrue);
    });
  });
}
