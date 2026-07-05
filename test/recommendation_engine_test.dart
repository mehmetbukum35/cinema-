import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';

Movie _movie(
  int id, {
  String? title,
  List<int> genres = const [28],
  double vote = 7.0,
  bool isTV = false,
}) {
  return Movie(
    id: id,
    title: title ?? 'Movie $id',
    overview: '',
    voteAverage: vote,
    genreIds: genres,
    isTV: isTV,
  );
}

void main() {
  group('RecommendationEngine.blend', () {
    test('keyword yokken 0.7/0.3 tür+puan harmanı uygular', () {
      final raw = RecommendationEngine.blend(genreSim: 0.5, voteAverage: 8.0);
      expect(raw, closeTo(0.7 * 0.5 + 0.3 * 0.8, 1e-9));
    });

    test('keyword varken 0.45/0.25/0.30 harmanı uygular', () {
      final raw = RecommendationEngine.blend(
        genreSim: 0.5,
        kwSim: 0.4,
        voteAverage: 8.0,
      );
      expect(raw, closeTo(0.45 * 0.5 + 0.25 * 0.4 + 0.3 * 0.8, 1e-9));
    });

    test('keyword sinyali skoru gerçekten ayrıştırır', () {
      final withKw = RecommendationEngine.blend(
        genreSim: 0.5,
        kwSim: 1.0,
        voteAverage: 7.0,
      );
      final withoutKw = RecommendationEngine.blend(
        genreSim: 0.5,
        kwSim: 0.0,
        voteAverage: 7.0,
      );
      expect(withKw, greaterThan(withoutKw));
    });
  });

  group('RecommendationEngine.toDisplayScore', () {
    test('[40, 98] sınırları içinde kalır', () {
      expect(RecommendationEngine.toDisplayScore(-5.0), 40);
      expect(RecommendationEngine.toDisplayScore(5.0), 98);
      final mid = RecommendationEngine.toDisplayScore(0.2);
      expect(mid, inInclusiveRange(40, 98));
    });

    test('monotoniktir: daha yüksek ham skor daha yüksek yüzde', () {
      final low = RecommendationEngine.toDisplayScore(0.1);
      final mid = RecommendationEngine.toDisplayScore(0.3);
      final high = RecommendationEngine.toDisplayScore(0.6);
      expect(mid, greaterThan(low));
      expect(high, greaterThan(mid));
    });

    test('cold-start ortalaması (0.2) skalanın ortasına düşer', () {
      // sigmoid(0) = 0.5 → 40 + 29 = 69
      expect(RecommendationEngine.toDisplayScore(0.2), 69);
    });
  });

  group('RecommendationEngine.applyFriendSignals', () {
    test('sinyalli aday boost alır ve arkadaş gerekçesi yazılır', () {
      final a = ScoredMovie(_movie(1), 0.5);
      final b = ScoredMovie(_movie(2), 0.5);
      RecommendationEngine.applyFriendSignals(
        [a, b],
        {
          'movie_1': ['Ayşe', 'Mehmet'],
        },
      );
      expect(a.score, closeTo(0.5 + 0.06 * 2, 1e-9));
      expect(a.movie.recoReason, 'Ayşe');
      expect(a.movie.recoReasonType, 'friend');
      expect(a.movie.recoSource, 'friend');
      expect(b.score, 0.5);
      expect(b.movie.recoReason, isNull);
    });

    test('boost en fazla maxFriends arkadaş sayar', () {
      final a = ScoredMovie(_movie(1), 0.0);
      RecommendationEngine.applyFriendSignals(
        [a],
        {
          'movie_1': ['A', 'B', 'C', 'D', 'E'],
        },
      );
      expect(a.score, closeTo(0.06 * 3, 1e-9));
    });

    test('tv anahtarı doğru eşleşir (tv_ öneki)', () {
      final a = ScoredMovie(_movie(7, isTV: true), 0.0);
      RecommendationEngine.applyFriendSignals(
        [a],
        {
          'tv_7': ['Zeynep'],
        },
      );
      expect(a.movie.recoReason, 'Zeynep');
    });
  });

  group('RecommendationEngine.applyDiversity', () {
    test('skor sırasını korur ama tür kopyalarını ayırır', () {
      // 3 aksiyon filmi üst üste + biraz düşük skorlu bir komedi:
      // çeşitlilik geçişi komediyi kopyaların arasına yükseltmeli.
      final action1 = ScoredMovie(_movie(1, genres: [28, 12]), 0.90);
      final action2 = ScoredMovie(_movie(2, genres: [28, 12]), 0.89);
      final action3 = ScoredMovie(_movie(3, genres: [28, 12]), 0.88);
      final comedy = ScoredMovie(_movie(4, genres: [35]), 0.85);

      final ordered = RecommendationEngine.applyDiversity([
        action1,
        action2,
        action3,
        comedy,
      ]);

      final ids = ordered.map((s) => s.movie.id).toList();
      // İlk seçim en yüksek skor olmalı.
      expect(ids.first, 1);
      // Komedi (id 4) son sıradan yukarı çıkmış olmalı: birebir aynı türdeki
      // action2/action3 tam Jaccard cezası yerken komedi ceza yemez.
      expect(ids.indexOf(4), lessThan(3));
    });

    test('2 veya daha az adayda sıralamaya dokunmaz', () {
      final a = ScoredMovie(_movie(1), 0.9);
      final b = ScoredMovie(_movie(2), 0.8);
      final ordered = RecommendationEngine.applyDiversity([a, b]);
      expect(ordered.map((s) => s.movie.id).toList(), [1, 2]);
    });

    test('eleman kaybetmez ve tekrar üretmez', () {
      final items = [
        for (var i = 0; i < 12; i++)
          ScoredMovie(_movie(i, genres: [28 + (i % 3)]), 1.0 - i * 0.05),
      ];
      final ordered = RecommendationEngine.applyDiversity(items);
      expect(ordered.length, items.length);
      expect(ordered.map((s) => s.movie.id).toSet().length, items.length);
    });
  });

  group('RecommendationEngine.jaccard', () {
    test('kesişim/birleşim oranını doğru hesaplar', () {
      expect(
        RecommendationEngine.jaccard([1, 2, 3], [2, 3, 4]),
        closeTo(0.5, 1e-9),
      );
      expect(RecommendationEngine.jaccard([1, 2], [1, 2]), 1.0);
      expect(RecommendationEngine.jaccard([1], [2]), 0.0);
      expect(RecommendationEngine.jaccard([], [1]), 0.0);
    });
  });

  group('RecommendationEngine.similarityScore', () {
    test('0.45/0.20/0.15/0.20 harmanını uygular', () {
      final s = RecommendationEngine.similarityScore(
        kwJaccard: 0.5,
        genreJaccard: 0.4,
        coVisit: true,
        voteAverage: 8.0,
      );
      expect(s, closeTo(0.45 * 0.5 + 0.20 * 0.4 + 0.15 + 0.20 * 0.8, 1e-9));
    });

    test('keyword örtüşmesi co-visit bonusundan güçlüdür', () {
      final kwOnly = RecommendationEngine.similarityScore(
        kwJaccard: 0.6,
        genreJaccard: 0,
        coVisit: false,
        voteAverage: 7.0,
      );
      final coVisitOnly = RecommendationEngine.similarityScore(
        kwJaccard: 0,
        genreJaccard: 0,
        coVisit: true,
        voteAverage: 7.0,
      );
      expect(kwOnly, greaterThan(coVisitOnly));
    });
  });

  group('RecommendationEngine.suppressFranchiseDuplicates', () {
    test('aynı serinin devamlarını eler, en iyi skorluyu tutar', () {
      final ordered = [
        _movie(1, title: 'Iron Man'),
        _movie(2, title: 'Iron Man 2'),
        _movie(3, title: 'The Dark Knight'),
        _movie(4, title: 'Iron Man 3'),
      ];
      final kept = RecommendationEngine.suppressFranchiseDuplicates(ordered);
      expect(kept.map((m) => m.id).toList(), [1, 3]);
    });

    test('farklı alt başlıklı seri filmleri (prefix değil) korunur', () {
      final ordered = [
        _movie(1, title: 'Batman Begins'),
        _movie(2, title: 'Batman Returns'),
      ];
      final kept = RecommendationEngine.suppressFranchiseDuplicates(ordered);
      expect(kept.length, 2);
    });

    test('kısa başlıklar (<5 karakter) yanlış pozitiften muaftır', () {
      final ordered = [_movie(1, title: 'Up'), _movie(2, title: 'Us')];
      final kept = RecommendationEngine.suppressFranchiseDuplicates(ordered);
      expect(kept.length, 2);
    });
  });
}
