import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'mocks/secure_storage_mock.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSecureStorageMock();

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

  group('RecommendationEngine Negative Signals Integration Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsService.resetAll();
    });

    test(
      'buildUserKeywordVector, Berbat (0) ve Eh (1) oylarına negatif ağırlık vermelidir',
      () async {
        // Mock ratings: ID 10 (Harika=3), ID 20 (Berbat=0)
        await PrefsService.saveRating(
          movieId: 10,
          isTV: false,
          rating: 3,
          genreIds: [28],
        );
        await PrefsService.saveRating(
          movieId: 20,
          isTV: false,
          rating: 0,
          genreIds: [35],
        );

        final client = MockClient((request) async {
          if (request.url.path.contains('/10/keywords')) {
            return http.Response(
              jsonEncode({
                'keywords': [
                  {'id': 100, 'name': 'action'},
                ],
              }),
              200,
            );
          } else if (request.url.path.contains('/20/keywords')) {
            return http.Response(
              jsonEncode({
                'keywords': [
                  {'id': 200, 'name': 'comedy'},
                ],
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final service = TmdbService(client: client);
        final engine = RecommendationEngine(service);

        final vector = await engine.buildUserKeywordVector();

        // Harika olanın keywordü pozitif olmalı, Berbat olanınki negatif
        expect(vector[100], greaterThan(0.0));
        expect(vector[200], lessThan(0.0));
      },
    );

    test(
      'rankForYou, Berbat oylanan filmlerin benzerlerini ve devam serilerini filtrelemelidir',
      () async {
        // Berbat oylanan film: "Iron Man" (ID: 50)
        await PrefsService.saveRating(
          movieId: 50,
          isTV: false,
          rating: 0,
          genreIds: [28],
          comment: 'bad',
        );
        // Biz "Iron Man" filminin title'ını test veritabanında kaydetmek için saveRating'e movie nesnesini de vermeliyiz.
        // DatabaseHelper mock'u `movie` parametresi verilirse başlığı oradan çeker:
        final movieObj = _movie(50, title: 'Iron Man');
        await PrefsService.saveRating(movie: movieObj, rating: 0);

        final client = MockClient((request) async {
          // Berbat filmin similar/recommendation isteklerine ID: 51'i dönelim (similar to Iron Man)
          if (request.url.path.contains('/50/recommendations') ||
              request.url.path.contains('/50/similar')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 51,
                    'title': 'Iron Man Similar',
                    'vote_average': 7.5,
                    'genre_ids': [28],
                    'poster_path': '/p.jpg',
                    'vote_count': 100,
                  },
                ],
              }),
              200,
            );
          }
          // Boş keyword dön
          return http.Response(jsonEncode({'keywords': []}), 200);
        });

        final service = TmdbService(client: client);
        final engine = RecommendationEngine(service);

        // Adaylar:
        // 1. Movie 99 (Alakasız film)
        // 2. Movie 51 (Iron Man'in benzeri -> berbatKeys içinde filtrelenmeli)
        // 3. Movie 102 (Başlığı "Iron Man 2" -> franchise filtresi ile elenmeli)
        final candidates = [
          _movie(99, title: 'Inception'),
          _movie(51, title: 'Iron Man Similar'),
          _movie(102, title: 'Iron Man 2'),
        ];

        final ranked = await engine.rankForYou(candidates);

        // Sadece 'Inception' (99) kalmalı
        expect(ranked.length, 1);
        expect(ranked.first.id, 99);
      },
    );
  });

  group('RecommendationEngine Fallback Seeds Integration Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsService.resetAll();
    });

    test(
      'fetchSeedCandidates, oylama yoksa sırasıyla Favoriler ve Watchlist tohumlarını kullanmalıdır',
      () async {
        // 1. Favorilere "Fav Movie" (ID: 200) ekle
        final favMovie = _movie(200, title: 'Fav Movie');
        await PrefsService.saveFavoriteMovies([favMovie]);

        // 2. Watchlist'e "Watchlist Movie" (ID: 300) ekle
        final watchMovie = _movie(300, title: 'Watchlist Movie');
        await PrefsService.addToWatchlist(watchMovie);

        final client = MockClient((request) async {
          // ID 200 ve 300 için mock responses
          if (request.url.path.contains('/200/recommendations') ||
              request.url.path.contains('/200/similar')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 201,
                    'title': 'Fav Movie Similar',
                    'vote_average': 8.0,
                    'genre_ids': [28],
                    'poster_path': '/fav.jpg',
                    'vote_count': 100,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.contains('/300/recommendations') ||
              request.url.path.contains('/300/similar')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 301,
                    'title': 'Watchlist Movie Similar',
                    'vote_average': 7.0,
                    'genre_ids': [28],
                    'poster_path': '/watch.jpg',
                    'vote_count': 100,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'results': []}), 200);
        });

        final service = TmdbService(client: client);
        final engine = RecommendationEngine(service);

        // seedCount: 2 veriyoruz. İlk tohum favori (200), ikinci tohum watchlist (300) olmalı.
        final seeds = await engine.fetchSeedCandidates(seedCount: 2);

        // Toplamda 4 aday (200 için similarity + recommendations, 300 için similarity + recommendations)
        // Ancak bizim mock client her istek için 1 film dönüyor. Yani her tohum için 2 film. Toplam 4 film olmalı.
        expect(seeds.length, 4);

        // Gerekçeleri kontrol et: en az bir tanesi favori, diğeri watchlist başlığı olmalı.
        final reasons = seeds.map((m) => m.recoReason).toSet();
        expect(reasons.contains('Fav Movie'), isTrue);
        expect(reasons.contains('Watchlist Movie'), isTrue);
      },
    );
  });

  group('RecommendationEngine Adaptive Telemetry Integration Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsService.resetAll();
    });

    test(
      'fetchSeedCandidates, tohum telemetrisi iyi ise tohum sayısını dinamik olarak artırmalıdır (6ya kadar)',
      () async {
        // 1. Telemetriyi mock SharedPreferences'a kaydet (seed=8/10, discover=2/10)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'reco_telemetry_v1',
          jsonEncode({
            'seed': {'shown': 10, 'liked': 8},
            'discover': {'shown': 10, 'liked': 2},
          }),
        );

        // 2. Ratings veritabanına 6 tane "Harika" film kaydet
        for (int i = 1; i <= 6; i++) {
          final movie = _movie(100 + i, title: 'Seed Movie $i');
          await PrefsService.saveRating(movie: movie, rating: 3);
        }

        final client = MockClient((request) async {
          // Her tohum isteğine 1 adet film dön
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 999,
                  'title': 'Recommendation',
                  'vote_average': 7.0,
                  'genre_ids': [28],
                  'poster_path': '/p.jpg',
                  'vote_count': 100,
                },
              ],
            }),
            200,
          );
        });

        final service = TmdbService(client: client);
        final engine = RecommendationEngine(service);

        // seedCount normalde 3 ama telemetriye göre 6'ya genişlemeli
        final seeds = await engine.fetchSeedCandidates(seedCount: 3);

        // 6 tohum * 2 istek (recommendations + similar) * 1 film = 12 aday
        expect(seeds.length, 12);
      },
    );
  });

  group('RecommendationEngine Cache Invalidation Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsService.resetAll();
    });

    test(
      'invalidateCache, veritabanı oylamaları ve keyword vektörü önbelleğini doğru şekilde temizlemelidir',
      () async {
        // Mock TMDB Client: film keyword'lerini döner
        final client = MockClient((request) async {
          if (request.url.path.contains('/100/keywords')) {
            return http.Response(
              jsonEncode({
                'keywords': [
                  {'id': 10, 'name': 'action'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.contains('/200/keywords')) {
            return http.Response(
              jsonEncode({
                'keywords': [
                  {'id': 20, 'name': 'scifi'},
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'keywords': []}), 200);
        });

        final service = TmdbService(client: client);
        final engine = RecommendationEngine(service);

        // 1. Birinci filmi oyla (ID: 100)
        await PrefsService.saveRating(
          movie: _movie(100, title: 'Action Movie'),
          rating: 3,
        );

        // 2. Keyword vektörünü hesapla (bu işlem sonucu önbelleklenir)
        final vector1 = await engine.buildUserKeywordVector();
        expect(vector1.containsKey(10), isTrue);
        expect(vector1.containsKey(20), isFalse);

        // 3. İkinci filmi oyla (ID: 200) ama henüz önbelleği temizleme
        await PrefsService.saveRating(
          movie: _movie(200, title: 'Scifi Movie'),
          rating: 3,
        );

        // Önbellek temizlenmediği için vektör hala eski değeri dönecektir
        final vector2 = await engine.buildUserKeywordVector();
        expect(vector2.containsKey(20), isFalse);

        // 4. Önbelleği temizle (invalidateCache)
        engine.invalidateCache();

        // Şimdi yeni filmin verileri de yüklenmelidir
        final vector3 = await engine.buildUserKeywordVector();
        expect(vector3.containsKey(10), isTrue);
        expect(vector3.containsKey(20), isTrue);
      },
    );
  });
}
