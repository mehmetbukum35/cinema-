import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  group('PrefsService Unit Tests', () {
    test(
      'getLikedGenreIds should calculate correct weighted genre ranks',
      () async {
        // 1. Initial genres: Action (28), comedy (35) -> Weight 1 each
        await PrefsService.saveInitialGenres([28, 35]);

        // 2. Favourites: Drama (18), Sci-Fi (878) -> Weight 3 each
        // Add one favorite movie with genres [18, 878]
        final favoriteMovie = Movie(
          id: 1,
          title: 'Fav Movie',
          overview: 'overview',
          voteAverage: 8.0,
          genreIds: [18, 878],
        );
        await PrefsService.saveFavoriteMovies([favoriteMovie]);

        // 3. Ratings >= 2 (İyi/Harika): Thriller (53) -> Weight 2
        // Rate movie 2 (rating: 3, genres: [53])
        await PrefsService.saveRating(
          movieId: 2,
          isTV: false,
          rating: 3,
          genreIds: [53],
        );

        // Score calculation:
        // - Genre 18: 3 (favorite)
        // - Genre 878: 3 (favorite)
        // - Genre 53: 2 (rated 3 >= 2)
        // - Genre 28: 1 (initial)
        // - Genre 35: 1 (initial)
        //
        // Top 3 should be: [18, 878, 53] (order of 18 and 878 can be arbitrary as they tie, but both must be in top 3)

        final likedGenres = await PrefsService.getLikedGenreIds();

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

    test(
      'getStats should return correct rating counts and top genres',
      () async {
        // Rate 3 movies:
        // Movie 1: rating 0 (Berbat), genres [28]
        // Movie 2: rating 2 (İyi), genres [35]
        // Movie 3: rating 3 (Harika), genres [35, 18]
        await PrefsService.saveRating(
          movieId: 10,
          isTV: false,
          rating: 0,
          genreIds: [28],
        );
        await PrefsService.saveRating(
          movieId: 11,
          isTV: false,
          rating: 2,
          genreIds: [35],
        );
        await PrefsService.saveRating(
          movieId: 12,
          isTV: false,
          rating: 3,
          genreIds: [35, 18],
        );

        final stats = await PrefsService.getStats();

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

        expect(await PrefsService.isInWatchlist(100, false), isFalse);

        await PrefsService.addToWatchlist(m);
        expect(await PrefsService.isInWatchlist(100, false), isTrue);

        final list = await PrefsService.getWatchlist();
        expect(list.length, 1);
        expect(list.first.id, 100);

        await PrefsService.removeFromWatchlist(100, false);
        expect(await PrefsService.isInWatchlist(100, false), isFalse);
        expect(await PrefsService.getWatchlist(), isEmpty);
      },
    );

    test(
      'saveRating and getRating should save and load comment and spoiler tag correctly',
      () async {
        await PrefsService.saveRating(
          movieId: 50,
          isTV: false,
          rating: 3,
          genreIds: [28],
          comment: 'Highly recommended masterpiece!',
          isSpoiler: 1,
        );

        final ratingData = await PrefsService.getRating(50, false);
        expect(ratingData, isNotNull);
        expect(ratingData!['rating'], 3);
        expect(ratingData['comment'], 'Highly recommended masterpiece!');
        expect(ratingData['is_spoiler'], 1);

        await PrefsService.saveRating(
          movieId: 50,
          isTV: false,
          rating: 2,
          genreIds: [28],
          comment: 'Actually it is just good.',
          isSpoiler: 0,
        );

        final ratingData2 = await PrefsService.getRating(50, false);
        expect(ratingData2!['rating'], 2);
        expect(ratingData2['comment'], 'Actually it is just good.');
        expect(ratingData2['is_spoiler'], 0);
      },
    );

    test(
      'revertRecoOutcome should correctly decrement recommendation telemetry counters',
      () async {
        // Record outcomes
        await PrefsService.recordRecoOutcome(source: 'discover', liked: true);
        await PrefsService.recordRecoOutcome(source: 'discover', liked: false);
        await PrefsService.recordRecoOutcome(source: 'discover', liked: true);

        var telemetry = await PrefsService.getRecoTelemetry();
        expect(telemetry['discover']?['shown'], 3);
        expect(telemetry['discover']?['liked'], 2);

        // Revert one liked outcome
        await PrefsService.revertRecoOutcome(source: 'discover', liked: true);
        telemetry = await PrefsService.getRecoTelemetry();
        expect(telemetry['discover']?['shown'], 2);
        expect(telemetry['discover']?['liked'], 1);

        // Revert one disliked outcome
        await PrefsService.revertRecoOutcome(source: 'discover', liked: false);
        telemetry = await PrefsService.getRecoTelemetry();
        expect(telemetry['discover']?['shown'], 1);
        expect(telemetry['discover']?['liked'], 1);

        // Revert another liked outcome
        await PrefsService.revertRecoOutcome(source: 'discover', liked: true);
        telemetry = await PrefsService.getRecoTelemetry();
        expect(telemetry['discover']?['shown'], 0);
        expect(telemetry['discover']?['liked'], 0);

        // Revert when already 0 should not go negative
        await PrefsService.revertRecoOutcome(source: 'discover', liked: true);
        telemetry = await PrefsService.getRecoTelemetry();
        expect(telemetry['discover']?['shown'], 0);
        expect(telemetry['discover']?['liked'], 0);
      },
    );
  });
}
