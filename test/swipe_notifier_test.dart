import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/providers/swipe_provider.dart';
import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
  });

  group('SwipeNotifier Business Logic Unit Tests', () {
    test(
      'init should load popular movies/shows, merge and filter already rated',
      () async {
        // Mock API responses
        final mockMovies = {
          'results': [
            {
              'id': 1,
              'title': 'Movie 1',
              'vote_average': 7.0,
              'genre_ids': [28],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final mockTv = {
          'results': [
            {
              'id': 2,
              'name': 'TV 1',
              'vote_average': 8.5,
              'genre_ids': [35],
              'poster_path': '/path2.jpg',
              'vote_count': 100,
            },
          ],
        };

        // Set up pre-rated movies in mock SharedPreferences/DB
        // Movie 1 (id: 1) is already rated
        await PrefsService.saveRating(
          movieId: 1,
          isTV: false,
          rating: 3,
          genreIds: [28],
        );

        final client = MockClient((request) async {
          if (request.url.path.endsWith('/3/movie/popular') ||
              request.url.path.endsWith('/3/discover/movie')) {
            return http.Response(jsonEncode(mockMovies), 200);
          } else if (request.url.path.endsWith('/3/tv/popular') ||
              request.url.path.endsWith('/3/discover/tv')) {
            return http.Response(jsonEncode(mockTv), 200);
          }
          return http.Response('Not Found', 404);
        });

        final service = TmdbService(client: client);
        final notifier = SwipeNotifier(service);

        // Wait for async init() to complete
        await Future.delayed(const Duration(milliseconds: 100));

        final state = notifier.state;

        // Expect Movie 1 (id: 1) to be filtered out, so queue contains only TV 1 (id: 2)
        expect(state.loading, isFalse);
        expect(state.queue.length, 1);
        expect(state.queue.first.id, 2);
        expect(state.ratedIds.contains('movie_1'), isTrue);
        expect(state.current, 0);
      },
    );

    test(
      'rate should increment current index, save to database and add to ratedIds',
      () async {
        final mockMovies = {
          'results': [
            {
              'id': 10,
              'title': 'Movie 10',
              'vote_average': 7.0,
              'genre_ids': [28],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final mockTv = {
          'results': [
            {
              'id': 20,
              'name': 'TV 20',
              'vote_average': 8.5,
              'genre_ids': [35],
              'poster_path': '/path2.jpg',
              'vote_count': 100,
            },
          ],
        };

        final client = MockClient((request) async {
          if (request.url.path.endsWith('/3/movie/popular') ||
              request.url.path.endsWith('/3/discover/movie')) {
            return http.Response(jsonEncode(mockMovies), 200);
          } else if (request.url.path.endsWith('/3/tv/popular') ||
              request.url.path.endsWith('/3/discover/tv')) {
            return http.Response(jsonEncode(mockTv), 200);
          }
          return http.Response('Not Found', 404);
        });

        final service = TmdbService(client: client);
        final notifier = SwipeNotifier(service);

        await Future.delayed(const Duration(milliseconds: 100));

        // Initial state: queue has 2 items, current = 0
        expect(notifier.state.queue.length, 2);
        expect(notifier.state.current, 0);

        final firstMovie = notifier.state.queue.first;
        final expectedKey =
            "${firstMovie.isTV ? 'tv' : 'movie'}_${firstMovie.id}";

        // Rate first movie as 'Harika' (3)
        await notifier.rate(3);

        // Expect current index to become 1, and first movie added to ratedIds
        expect(notifier.state.current, 1);
        expect(notifier.state.ratedIds.contains(expectedKey), isTrue);

        // Verify that it saved to DatabaseHelper
        var ratedIds = await PrefsService.getRatedIds();
        expect(ratedIds.contains(expectedKey), isTrue);

        // Undo should bring current back to 0
        await notifier.undo();
        expect(notifier.state.current, 0);
        expect(notifier.state.ratedIds.contains(expectedKey), isFalse);

        // Verify that it rolled back in DB
        ratedIds = await PrefsService.getRatedIds();
        expect(ratedIds.contains(expectedKey), isFalse);
      },
    );

    test(
      'loadMore should be guarded against concurrent calls and deduplicate queue',
      () async {
        final mockMovies = {
          'results': [
            {
              'id': 100,
              'title': 'Movie 100',
              'vote_average': 7.0,
              'genre_ids': [28],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final mockTv = {
          'results': [
            {
              'id': 200,
              'name': 'TV 200',
              'vote_average': 8.5,
              'genre_ids': [35],
              'poster_path': '/path2.jpg',
              'vote_count': 100,
            },
          ],
        };

        var apiCallCount = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/3/movie/popular') ||
              request.url.path.endsWith('/3/tv/popular')) {
            apiCallCount++;
            // Simulate some network delay
            await Future.delayed(const Duration(milliseconds: 50));
            if (request.url.path.endsWith('/3/movie/popular')) {
              return http.Response(jsonEncode(mockMovies), 200);
            } else if (request.url.path.endsWith('/3/tv/popular')) {
              return http.Response(jsonEncode(mockTv), 200);
            }
          }
          return http.Response('Not Found', 404);
        });

        final service = TmdbService(client: client);
        final notifier = SwipeNotifier(service);

        // Wait for initial load to finish (which calls loadMore once)
        await Future.delayed(const Duration(milliseconds: 150));

        // Initial load should make 2 calls (1 movie popular, 1 tv popular)
        expect(apiCallCount, 2);
        expect(notifier.state.queue.length, 2);

        // Trigger loadMore multiple times concurrently
        final futures = <Future<void>>[
          notifier.loadMore(),
          notifier.loadMore(),
          notifier.loadMore(),
        ];

        await Future.wait(futures);

        // Even though loadMore was triggered 3 times, since the first one locks it,
        // it should only make 2 more API calls (total 4) instead of 6 more (total 8).
        expect(apiCallCount, 4);

        // Queue length should still be 2 because the mock returns the same items
        // and they are deduplicated against the existing items in the queue.
        expect(notifier.state.queue.length, 2);
      },
    );

    test(
      'updateFilters should reset queue, update state filters and fetch from discover endpoint',
      () async {
        final mockDiscoverMovies = {
          'results': [
            {
              'id': 300,
              'title': 'Korean Movie',
              'vote_average': 8.0,
              'genre_ids': [18],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final mockDiscoverTv = {
          'results': [
            {
              'id': 400,
              'name': 'Korean Show',
              'vote_average': 7.5,
              'genre_ids': [18],
              'poster_path': '/path2.jpg',
              'vote_count': 100,
            },
          ],
        };

        var discoverCallCount = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/3/movie/popular')) {
            return http.Response(jsonEncode({'results': []}), 200);
          } else if (request.url.path.endsWith('/3/tv/popular')) {
            return http.Response(jsonEncode({'results': []}), 200);
          } else if (request.url.path.endsWith('/3/discover/movie')) {
            discoverCallCount++;
            expect(request.url.queryParameters['with_original_language'], 'ko');
            expect(request.url.queryParameters['with_watch_providers'], '8');
            return http.Response(jsonEncode(mockDiscoverMovies), 200);
          } else if (request.url.path.endsWith('/3/discover/tv')) {
            discoverCallCount++;
            expect(request.url.queryParameters['with_original_language'], 'ko');
            expect(request.url.queryParameters['with_watch_providers'], '8');
            return http.Response(jsonEncode(mockDiscoverTv), 200);
          }
          return http.Response('Not Found', 404);
        });

        final service = TmdbService(client: client);
        final notifier = SwipeNotifier(service);

        await Future.delayed(const Duration(milliseconds: 50));
        expect(notifier.state.queue.isEmpty, isTrue);

        await notifier.updateFilters(languageFilter: 'ko', providerFilter: 8);

        expect(notifier.state.languageFilter, 'ko');
        expect(notifier.state.providerFilter, 8);
        expect(discoverCallCount, 2);
        expect(notifier.state.queue.length, 2);
        expect(notifier.state.queue.any((m) => m.id == 300), isTrue);
        expect(notifier.state.queue.any((m) => m.id == 400), isTrue);
      },
    );
    test('should handle "no more content" condition correctly', () async {
      // Mock API returning empty results
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'results': []}), 200);
      });
      final service = TmdbService(client: client);
      final notifier = SwipeNotifier(service);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.queue, isEmpty);
      expect(notifier.state.loading, isFalse);
    });
  });
}
