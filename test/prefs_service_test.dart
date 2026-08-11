import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs/app_settings.dart';
import 'package:ne_izlesem/services/prefs/auth_storage.dart';
import 'package:ne_izlesem/services/prefs/taste_prefs.dart';
import 'package:ne_izlesem/services/prefs/library_facade.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    // Initialize SharedPreferences with empty mock values before each test
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
  });

  group('PrefsTastePrefs genre weights (via PrefsService)', () {
    test(
      'getLikedGenreIds should calculate correct weighted genre ranks',
      () async {
        // 1. Initial genres: Action (28), comedy (35) -> Weight 1 each
        await PrefsTastePrefs.saveInitialGenres([28, 35]);

        // 2. Favourites: Drama (18), Sci-Fi (878) -> Weight 3 each
        // Add one favorite movie with genres [18, 878]
        final favoriteMovie = Movie(
          id: 1,
          title: 'Fav Movie',
          overview: 'overview',
          voteAverage: 8.0,
          genreIds: [18, 878],
        );
        await PrefsLibraryFacade.saveFavoriteMovies([
          favoriteMovie,
        ], metadataLocale: 'tr');

        // 3. Ratings >= 2 (İyi/Harika): Thriller (53) -> Weight 2
        // Rate movie 2 (rating: 3, genres: [53])
        await PrefsLibraryFacade.saveRating(
          movieId: 2,
          isTV: false,
          rating: 3,
          genreIds: [53],

          metadataLocale: 'tr',
        );

        // Score calculation:
        // - Genre 18: 3 (favorite)
        // - Genre 878: 3 (favorite)
        // - Genre 53: 2 (rated 3 >= 2)
        // - Genre 28: 1 (initial)
        // - Genre 35: 1 (initial)
        //
        // Top 3 should be: [18, 878, 53] (order of 18 and 878 can be arbitrary as they tie, but both must be in top 3)

        final likedGenres = await PrefsTastePrefs.getLikedGenreIds();

        expect(likedGenres.length, lessThanOrEqualTo(3));
        expect(likedGenres.contains(18), isTrue);
        expect(likedGenres.contains(878), isTrue);
        expect(likedGenres.contains(53), isTrue);
        expect(
          likedGenres.contains(28),
          isFalse,
        ); // action should not be in top 3
        expect(
          likedGenres.contains(35),
          isFalse,
        ); // comedy should not be in top 3
      },
    );

    test('favorites feed genre weights by rank (no decay-to-zero)', () async {
      // #1 favori → tür 18, #2 favori → tür 27 (aynı listede, farklı sıra).
      await PrefsLibraryFacade.saveFavoriteMovies([
        Movie(id: 1, title: 'A', overview: '', voteAverage: 8, genreIds: [18]),
        Movie(id: 2, title: 'B', overview: '', voteAverage: 8, genreIds: [27]),
      ], metadataLocale: 'tr');

      final w = await PrefsTastePrefs.getGenreWeights();
      // Favoriler artık cihazda da katkı veriyor (created_at = sıra, decay yok).
      expect((w[18] ?? 0) > 0, isTrue);
      expect((w[27] ?? 0) > 0, isTrue);
      // #1 (rank 0) tam taban katsayısını (3.0) alır; #2 (rank 1) biraz daha az.
      expect(w[18]!, closeTo(3.0, 1e-9));
      expect(w[18]! > w[27]!, isTrue);
    });

    test('recordRecoShown kaynak başına sayar ve atıfsızları eler', () async {
      await PrefsTastePrefs.recordRecoShown([
        'discover',
        'seed',
        null,
        'discover',
      ]);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 2);
      expect(telemetry['discover']?['liked'], 0);
      expect(telemetry['seed']?['shown'], 1);
      expect(telemetry.keys, isNot(contains('null')));
    });

    test('recordRecoLiked yalnız liked sayacını artırır', () async {
      await PrefsTastePrefs.recordRecoShown([
        'discover',
        'discover',
        'discover',
      ]);
      await PrefsTastePrefs.recordRecoLiked('discover');
      await PrefsTastePrefs.recordRecoLiked('discover');
      await PrefsTastePrefs.recordRecoLiked(null);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 3);
      expect(telemetry['discover']?['liked'], 2);
    });

    test('revertRecoLiked gösterim sayacına dokunmaz', () async {
      await PrefsTastePrefs.recordRecoShown(['discover', 'discover']);
      await PrefsTastePrefs.recordRecoLiked('discover');

      await PrefsTastePrefs.revertRecoLiked('discover');

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 2);
      expect(telemetry['discover']?['liked'], 0);
    });

    test('yeniden puanlama liked <= shown değişmezini korur', () async {
      // Tek gösterim, ardından 2 → 3 yeniden puanlaması: ekran önce eskiyi
      // geri alır, sonra yenisini yazar. `liked` 1'de kalmalı, `shown` 1'de.
      await PrefsTastePrefs.recordRecoShown(['discover']);

      await PrefsTastePrefs.recordRecoLiked('discover');
      await PrefsTastePrefs.revertRecoLiked('discover');
      await PrefsTastePrefs.recordRecoLiked('discover');

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 1);
      expect(telemetry['discover']?['liked'], 1);

      // 3 → 1 düşürmesi: yalnız geri alma çalışır, kredi geri çekilir.
      await PrefsTastePrefs.revertRecoLiked('discover');

      final after = await PrefsTastePrefs.getRecoTelemetry();
      expect(after['discover']?['shown'], 1);
      expect(after['discover']?['liked'], 0);
    });

    test('revertRecoLiked negatife düşmez ve atıfsızı yok sayar', () async {
      await PrefsTastePrefs.revertRecoLiked('discover');
      await PrefsTastePrefs.revertRecoLiked(null);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['liked'], 0);
      expect(telemetry.keys, isNot(contains('null')));
    });

    test('eşzamanlı gösterim yazımları artışları kaybetmez', () async {
      await Future.wait(
        List.generate(50, (_) => PrefsTastePrefs.recordRecoShown(['discover'])),
      );

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 50);
    });

    test('v1 telemetri anahtarı okunmaz ve silinir', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'reco_telemetry_v1',
        jsonEncode({
          'discover': {'shown': 99, 'liked': 99},
        }),
      );

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();

      expect(telemetry['discover'], isNull);
      expect(prefs.getString('reco_telemetry_v1'), isNull);
    });

    test('bozuk telemetri yükü boş okunur', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('reco_telemetry_v2', 'json değil');

      expect(await PrefsTastePrefs.getRecoTelemetry(), isEmpty);
    });

    test('dismiss feedback prompt respects the daily cooldown', () async {
      expect(
        await PrefsTastePrefs.shouldAskDismissFeedback(matchScore: 80),
        isTrue,
      );
      expect(
        await PrefsTastePrefs.shouldAskDismissFeedback(matchScore: 95),
        isFalse,
      );
    });

    test(
      'dismiss feedback records its reason and recommendation source',
      () async {
        await PrefsTastePrefs.recordDismissFeedback(
          movieKey: 'movie_550',
          reason: 'notNow',
          source: 'culture',
        );

        final events = await PrefsTastePrefs.getDismissFeedback();
        expect(events, hasLength(1));
        expect(events.single['movie_key'], 'movie_550');
        expect(events.single['reason'], 'notNow');
        expect(events.single['source'], 'culture');
      },
    );

    test('resetAll invalidates cached genre weights', () async {
      await PrefsTastePrefs.saveInitialGenres([28]);
      expect(await PrefsTastePrefs.getGenreWeights(), contains(28));

      await PrefsService.resetAll();

      expect(await PrefsTastePrefs.getGenreWeights(), isEmpty);
    });
  });

  group('PrefsLibraryFacade (via PrefsService)', () {
    test('favoriteRankWeight: #1 tam, sona doğru azalır', () {
      expect(PrefsLibraryFacade.favoriteRankWeight(0), closeTo(1.0, 1e-9));
      expect(PrefsLibraryFacade.favoriteRankWeight(19), closeTo(0.2, 1e-9));
      // Sıra dışı (ör. bozuk) değerler güvenle kıstırılır.
      expect(PrefsLibraryFacade.favoriteRankWeight(999), closeTo(0.2, 1e-9));
      expect(
        PrefsLibraryFacade.favoriteRankWeight(0) >
            PrefsLibraryFacade.favoriteRankWeight(10),
        isTrue,
      );
    });

    test(
      'getStats should return correct rating counts and top genres',
      () async {
        // Rate 3 movies:
        // Movie 1: rating 0 (Berbat), genres [28]
        // Movie 2: rating 2 (İyi), genres [35]
        // Movie 3: rating 3 (Harika), genres [35, 18]
        await PrefsLibraryFacade.saveRating(
          movieId: 10,
          isTV: false,
          rating: 0,
          genreIds: [28],

          metadataLocale: 'tr',
        );
        await PrefsLibraryFacade.saveRating(
          movieId: 11,
          isTV: false,
          rating: 2,
          genreIds: [35],

          metadataLocale: 'tr',
        );
        await PrefsLibraryFacade.saveRating(
          movieId: 12,
          isTV: false,
          rating: 3,
          genreIds: [35, 18],

          metadataLocale: 'tr',
        );

        final stats = await PrefsLibraryFacade.getStats();

        expect(stats['total'], 3);
        expect(stats['berbat'], 1);
        expect(stats['eh'], 0);
        expect(stats['iyi'], 1);
        expect(stats['harika'], 1);

        // Top genres from ratings >= 2:
        // - Genre 35: 2 occurrences (movie 11 and 12)
        // - Genre 18: 1 occurrence (movie 12)
        // - Genre 28: 0 (rating was 0 < 2)
        final topGenres = stats['topGenres'] as List<int>;
        expect(topGenres.first, 35);
        expect(topGenres.contains(18), isTrue);
        expect(topGenres.contains(28), isFalse);
      },
    );

    test(
      'watchlist management should add and remove items correctly',
      () async {
        final m = Movie(
          id: 100,
          title: 'Watchlist Movie',
          overview: '...',
          voteAverage: 7.0,
          isTV: false,
        );

        expect(await PrefsLibraryFacade.isInWatchlist(100, false), isFalse);

        await PrefsLibraryFacade.addToWatchlist(m, metadataLocale: 'tr');
        expect(await PrefsLibraryFacade.isInWatchlist(100, false), isTrue);

        final list = await PrefsLibraryFacade.getWatchlist();
        expect(list.length, 1);
        expect(list.first.id, 100);

        await PrefsLibraryFacade.removeFromWatchlist(100, false);
        expect(await PrefsLibraryFacade.isInWatchlist(100, false), isFalse);
        expect(await PrefsLibraryFacade.getWatchlist(), isEmpty);
      },
    );

    test(
      'saveRating and getRating should save and load comment and spoiler tag correctly',
      () async {
        await PrefsLibraryFacade.saveRating(
          movieId: 50,
          isTV: false,
          rating: 3,
          genreIds: [28],
          comment: 'Highly recommended masterpiece!',
          isSpoiler: 1,

          metadataLocale: 'tr',
        );

        final ratingData = await PrefsLibraryFacade.getRating(50, false);
        expect(ratingData, isNotNull);
        expect(ratingData!['rating'], 3);
        expect(ratingData['comment'], 'Highly recommended masterpiece!');
        expect(ratingData['is_spoiler'], 1);

        await PrefsLibraryFacade.saveRating(
          movieId: 50,
          isTV: false,
          rating: 2,
          genreIds: [28],
          comment: 'Actually it is just good.',
          isSpoiler: 0,

          metadataLocale: 'tr',
        );

        final ratingData2 = await PrefsLibraryFacade.getRating(50, false);
        expect(ratingData2!['rating'], 2);
        expect(ratingData2['comment'], 'Actually it is just good.');
        expect(ratingData2['is_spoiler'], 0);
      },
    );

    // metadata_locale, onbellege alinan baslik metadatasinin hangi dilde
    // oldugunu soyler. Sabitlenirse Ingilizce oturumun verisi 'tr' etiketiyle
    // diske yazilir ve dil degisiminde yanlis metin gosterilir.
    test('saveRating verilen dili yazar, sabit deger degil', () async {
      await PrefsLibraryFacade.saveRating(
        movieId: 4242,
        isTV: false,
        rating: 5,
        metadataLocale: 'en',
      );
      await PrefsLibraryFacade.saveRating(
        movieId: 4343,
        isTV: false,
        rating: 4,
        metadataLocale: 'tr',
      );

      expect(
        (await DatabaseHelper().getRating(4242, false))?['metadata_locale'],
        'en',
      );
      expect(
        (await DatabaseHelper().getRating(4343, false))?['metadata_locale'],
        'tr',
      );
    });

    test('addToWatchlist verilen dili yazar', () async {
      final movie = Movie(
        id: 5151,
        title: 'Watch EN',
        overview: '',
        voteAverage: 7.0,
      );
      await PrefsLibraryFacade.addToWatchlist(movie, metadataLocale: 'en');

      final rows = await DatabaseHelper().getWatchlistRaw();
      final row = rows.singleWhere((r) => r['id'] == 5151);
      expect(row['metadata_locale'], 'en');
    });

    test(
      'saveFavoriteMovies ve saveFavoriteTvShows verilen dili yazar',
      () async {
        final film = Movie(
          id: 6161,
          title: 'Fav Film',
          overview: '',
          voteAverage: 8.0,
          isTV: false,
        );
        final show = Movie(
          id: 6262,
          title: 'Fav Show',
          overview: '',
          voteAverage: 8.0,
          isTV: true,
        );
        await PrefsLibraryFacade.saveFavoriteMovies([
          film,
        ], metadataLocale: 'en');
        await PrefsLibraryFacade.saveFavoriteTvShows([
          show,
        ], metadataLocale: 'tr');

        final rows = await DatabaseHelper().getFavoritesRaw();
        expect(
          rows.singleWhere((r) => r['id'] == 6161)['metadata_locale'],
          'en',
        );
        expect(
          rows.singleWhere((r) => r['id'] == 6262)['metadata_locale'],
          'tr',
        );
      },
    );
  });

  group('PrefsAuthStorage cache (via PrefsService)', () {
    // Access token secure storage'da tutulur ama her HTTP isteginde okumak
    // pahali oldugu icin bellekte cache'lenir. Cache statik oldugundan bir
    // testin yazdigi token sonraki testlere sizar; resetInMemoryCaches bunu
    // kirar.
    const accessTokenKey = 'auth_access_token';

    test(
      'resetInMemoryCaches cache ile depolama ayristiginda depolamayi okur',
      () async {
        await PrefsAuthStorage.saveTokens(
          accessToken: 'cached_value',
          refreshToken: 'cached_refresh',
        );
        // Depolamayi PrefsService'i atlayarak degistir: cache artik bayat.
        await const FlutterSecureStorage().write(
          key: accessTokenKey,
          value: 'storage_value',
        );
        expect(
          await PrefsAuthStorage.getAccessToken(),
          'cached_value',
          reason: 'cache canli olmali, aksi halde test bir sey kanitlamaz',
        );

        PrefsService.resetInMemoryCaches();

        expect(await PrefsAuthStorage.getAccessToken(), 'storage_value');
      },
    );

    test('saveTokens token depolamaya da yazar, yalniz cache degil', () async {
      await PrefsAuthStorage.saveTokens(
        accessToken: 'token_a',
        refreshToken: 'refresh_a',
      );

      PrefsService.resetInMemoryCaches();

      expect(await PrefsAuthStorage.getAccessToken(), 'token_a');
    });

    test('clearAuthData cache icindeki tokeni da dusurur', () async {
      await PrefsAuthStorage.saveTokens(
        accessToken: 'token_b',
        refreshToken: 'refresh_b',
      );
      expect(await PrefsAuthStorage.getAccessToken(), 'token_b');

      await PrefsService.clearAuthData();

      expect(await PrefsAuthStorage.getAccessToken(), isNull);
    });
  });

  group('PrefsAppSettings (via PrefsService)', () {
    test('tur adi verilen dile gore cozulur', () {
      expect(PrefsAppSettings.genreName(28, locale: 'tr'), 'Aksiyon');
      expect(PrefsAppSettings.genreName(28, locale: 'en'), 'Action');
    });

    test('bilinmeyen tur id dile uygun yedek dondurur', () {
      expect(PrefsAppSettings.genreName(999999, locale: 'tr'), 'Bilinmeyen');
      expect(PrefsAppSettings.genreName(999999, locale: 'en'), 'Unknown');
    });
  });
}
