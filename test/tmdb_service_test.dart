import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/models/movie.dart';

void main() {
  group('TmdbService Unit Tests with MockClient', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseHelper().clearTmdbCache();
    });

    test('searchMulti should parse results and map to Movie objects', () async {
      final mockResponse = {
        'results': [
          {
            'id': 101,
            'media_type': 'movie',
            'title': 'Mock Movie 1',
            'overview': 'Overview 1',
            'vote_average': 7.5,
            'release_date': '2026-01-01',
            'genre_ids': [28],
            'poster_path': '/path1.jpg',
            'vote_count': 100,
          },
          {
            'id': 102,
            'media_type': 'tv',
            'name': 'Mock TV Show 1',
            'overview': 'Overview 2',
            'vote_average': 8.2,
            'first_air_date': '2025-05-05',
            'genre_ids': [35],
            'poster_path': '/path2.jpg',
            'vote_count': 100,
          },
          {
            'id': 103,
            'media_type': 'person', // Should be ignored by searchMulti
            'name': 'Famous Person',
          },
        ],
      };

      final client = MockClient((request) async {
        expect(request.url.path.endsWith('/3/search/multi'), isTrue);
        expect(request.url.queryParameters['query'], 'Inception');
        return http.Response(
          jsonEncode(mockResponse),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = TmdbService(client: client);
      final results = await service.searchMulti('Inception');

      expect(results.length, 2);
      expect(results[0].id, 101);
      expect(results[0].title, 'Mock Movie 1');
      expect(results[0].isTV, isFalse);

      expect(results[1].id, 102);
      expect(results[1].title, 'Mock TV Show 1');
      expect(results[1].isTV, isTrue);
    });

    test(
      'searchMulti should throw TmdbApiException on HTTP non-200 status code',
      () async {
        final client = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final service = TmdbService(client: client);
        expect(
          () => service.searchMulti('Inception'),
          throwsA(isA<TmdbApiException>()),
        );
      },
    );

    test('getReviews should filter short reviews and limit to top 5', () async {
      final mockResponse = {
        'results': [
          {
            'author': 'Reviewer A',
            'content':
                'Short review.', // under 20 chars, should be filtered out
          },
          {
            'author': 'Reviewer B',
            'content':
                'This is a sufficiently long movie review to pass the filter.',
          },
        ],
      };

      final client = MockClient((request) async {
        expect(request.url.path.endsWith('/3/movie/123/reviews'), isTrue);
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final service = TmdbService(client: client);
      final reviews = await service.getReviews(123, isTV: false);

      expect(reviews.length, 1);
      expect(reviews[0].author, 'Reviewer B');
      expect(
        reviews[0].content,
        'This is a sufficiently long movie review to pass the filter.',
      );
    });

    test(
      'getTrailerKey should query Turkish first, then fallback to English if not found',
      () async {
        var callCount = 0;

        final client = MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            // Turkish request
            expect(request.url.path.endsWith('/3/movie/789/videos'), isTrue);
            expect(request.url.queryParameters['language'], 'tr-TR');
            // Return empty results to trigger fallback
            return http.Response(jsonEncode({'results': []}), 200);
          } else {
            // English fallback request
            expect(request.url.path.endsWith('/3/movie/789/videos'), isTrue);
            expect(request.url.queryParameters['language'], 'en-US');
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'site': 'YouTube',
                    'type': 'Trailer',
                    'official': true,
                    'key': 'EN_KEY_123',
                  },
                ],
              }),
              200,
            );
          }
        });

        final service = TmdbService(client: client);
        final trailerKey = await service.getTrailerKey(789, isTV: false);

        expect(trailerKey, 'EN_KEY_123');
        expect(callCount, 2);
      },
    );

    // Movie 1: lower rating (7.0) but higher popularity (500)
    // TV 2:    higher rating (8.5) but lower popularity (100)
    // -> Different sort criteria must produce different orderings.
    final mockMovies = {
      'results': [
        {
          'id': 1,
          'title': 'Movie 1',
          'vote_average': 7.0,
          'popularity': 500.0,
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
          'popularity': 100.0,
          'genre_ids': [35],
          'poster_path': '/path2.jpg',
          'vote_count': 100,
        },
      ],
    };
    MockClient discoverClient() => MockClient((request) async {
      if (request.url.path.endsWith('/3/discover/movie')) {
        return http.Response(jsonEncode(mockMovies), 200);
      } else if (request.url.path.endsWith('/3/discover/tv')) {
        return http.Response(jsonEncode(mockTv), 200);
      }
      return http.Response('Not Found', 404);
    });

    test(
      'discover should merge movie + TV and honor vote_average.desc sort',
      () async {
        final service = TmdbService(client: discoverClient());
        final results = await service.discover(
          genreStr: '28,35',
          includeMovies: true,
          includeTv: true,
          sortBy: 'vote_average.desc',
        );

        // Sorted by rating desc: TV 2 (8.5) before Movie 1 (7.0)
        expect(results.length, 2);
        expect(results[0].id, 2);
        expect(results[1].id, 1);
      },
    );

    test('discover should honor popularity.desc sort (default)', () async {
      final service = TmdbService(client: discoverClient());
      final results = await service.discover(
        genreStr: '28,35',
        includeMovies: true,
        includeTv: true,
      );

      // Default popularity.desc: Movie 1 (500) before TV 2 (100),
      // even though TV 2 has the higher rating.
      expect(results.length, 2);
      expect(results[0].id, 1);
      expect(results[1].id, 2);
    });

    test('discover should pass the requested page to the API', () async {
      String? capturedPage;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/3/discover/movie')) {
          capturedPage = request.url.queryParameters['page'];
          return http.Response(jsonEncode(mockMovies), 200);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      });

      final service = TmdbService(client: client);
      await service.discover(includeMovies: true, includeTv: false, page: 3);

      expect(capturedPage, '3');
    });

    test(
      'discoverByGenres should call discover with correct genre ids',
      () async {
        final mockResponse = {
          'results': [
            {
              'id': 101,
              'title': 'Movie 101',
              'genre_ids': [28, 35],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final client = MockClient((request) async {
          expect(request.url.path.endsWith('/3/discover/movie'), isTrue);
          expect(request.url.queryParameters['with_genres'], '28|35');
          return http.Response(jsonEncode(mockResponse), 200);
        });
        final service = TmdbService(client: client);
        final results = await service.discoverByGenres([28, 35]);
        expect(results, hasLength(1));
        expect(results[0].id, 101);
      },
    );

    test(
      'getRecommendations should return recommendations for a movie',
      () async {
        final mockResponse = {
          'results': [
            {
              'id': 202,
              'title': 'Rec Movie',
              'genre_ids': [12],
              'poster_path': '/path1.jpg',
              'vote_count': 100,
            },
          ],
        };
        final client = MockClient((request) async {
          expect(
            request.url.path.endsWith('/3/movie/123/recommendations'),
            isTrue,
          );
          return http.Response(jsonEncode(mockResponse), 200);
        });
        final service = TmdbService(client: client);
        final results = await service.getRecommendations(123, isTV: false);
        expect(results, hasLength(1));
        expect(results[0].id, 202);
      },
    );

    test('getTrending should return trending movies', () async {
      final mockResponse = {
        'results': [
          {
            'id': 303,
            'title': 'Trending Movie',
            'genre_ids': [28],
            'media_type': 'movie',
            'poster_path': '/path1.jpg',
            'vote_count': 100,
          },
        ],
      };
      final client = MockClient((request) async {
        expect(request.url.path.endsWith('/3/trending/all/week'), isTrue);
        return http.Response(jsonEncode(mockResponse), 200);
      });
      final service = TmdbService(client: client);
      final results = await service.getTrending();
      expect(results, hasLength(1));
      expect(results[0].id, 303);
    });

    test('should handle empty results gracefully', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'results': []}), 200);
      });
      final service = TmdbService(client: client);
      final results = await service.getTrending();
      expect(results, isEmpty);
    });

    test('should throw TmdbApiException on timeout/error', () async {
      final client = MockClient((request) async {
        throw Exception('Connection Timeout');
      });
      final service = TmdbService(client: client);
      expect(() => service.getTrending(), throwsA(isA<TmdbApiException>()));
    });

    test('should filter out blocked movie IDs from results lists', () async {
      SharedPreferences.setMockInitialValues({
        'blocked_movie_ids': ['movie_101'],
      });

      final mockResponse = {
        'results': [
          {
            'id': 101,
            'media_type': 'movie',
            'title': 'Blocked Movie',
            'overview': 'Some overview',
            'vote_average': 5.0,
            'release_date': '2026-01-01',
            'poster_path': '/path1.jpg',
            'vote_count': 100,
          },
          {
            'id': 102,
            'media_type': 'movie',
            'title': 'Safe Movie',
            'overview': 'Some overview',
            'vote_average': 8.0,
            'release_date': '2026-01-02',
            'poster_path': '/path2.jpg',
            'vote_count': 100,
          },
        ],
      };

      final client = MockClient((request) async {
        return http.Response(jsonEncode(mockResponse), 200);
      });
      final service = TmdbService(client: client);
      final results = await service.searchMulti('test');

      expect(results, hasLength(1));
      expect(results[0].id, 102);
      expect(results[0].title, 'Safe Movie');
    });

    test(
      'sanitizeListForTesting should filter out low quality items when forced',
      () async {
        final list = [
          Movie(
            id: 1,
            title: 'No Poster',
            voteCount: 100,
            overview: '',
            voteAverage: 7.0,
          ), // Filtered (no poster)
          Movie(
            id: 2,
            title: 'Low Votes',
            posterPath: '/p.jpg',
            voteCount: 5,
            overview: '',
            voteAverage: 7.0,
          ), // Filtered in default, kept in search
          Movie(
            id: 3,
            title: 'High Quality Movie',
            posterPath: '/p.jpg',
            voteCount: 100,
            overview: '',
            voteAverage: 7.0,
          ), // Kept
          Movie(
            id: 4,
            title: 'Search Border Movie',
            posterPath: '/p.jpg',
            voteCount: 4,
            overview: '',
            voteAverage: 7.0,
          ), // Kept in search, filtered in default
        ];

        final service = TmdbService(
          client: MockClient((_) async => http.Response('{}', 200)),
        );

        // 1. Default list sanitization (threshold = 15)
        final defaultList = await service.sanitizeListForTesting(
          list,
          isSearch: false,
        );
        expect(defaultList.map((m) => m.id).toList(), [3]);

        // 2. Search list sanitization (threshold = 3)
        final searchList = await service.sanitizeListForTesting(
          list,
          isSearch: true,
        );
        expect(searchList.map((m) => m.id).toList(), [2, 3, 4]);
      },
    );

    test(
      'Movie.clone should produce a distinct copy with identical properties',
      () {
        final original =
            Movie(
                id: 42,
                title: 'Original Title',
                overview: 'Overview text',
                voteAverage: 8.5,
                genreIds: [18, 28],
              )
              ..recoReason = 'Friend Recommendation'
              ..recoReasonType = 'friend'
              ..recoSource = 'friend';

        final clone = original.clone();

        expect(clone.id, original.id);
        expect(clone.title, original.title);
        expect(clone.overview, original.overview);
        expect(clone.voteAverage, original.voteAverage);
        expect(clone.genreIds, original.genreIds);
        expect(clone.recoReason, original.recoReason);
        expect(clone.recoReasonType, original.recoReasonType);
        expect(clone.recoSource, original.recoSource);

        // Mutate the clone
        clone.recoReason = 'New Reason';
        clone.recoReasonType = 'seed';
        clone.recoSource = 'seed';

        // Original should remain unchanged
        expect(original.recoReason, 'Friend Recommendation');
        expect(original.recoReasonType, 'friend');
        expect(original.recoSource, 'friend');
      },
    );

    test('getSimilar should return clones of cached movies', () async {
      final mockResponse = {
        'results': [
          {
            'id': 501,
            'title': 'Similar Movie',
            'overview': 'Overview',
            'vote_average': 7.0,
            'genre_ids': [18],
            'poster_path': '/path.jpg',
            'vote_count': 100,
          },
        ],
      };

      final client = MockClient((request) async {
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final service = TmdbService(client: client);

      // First fetch (cache miss)
      final firstFetch = await service.getSimilar(100);
      expect(firstFetch.length, 1);
      firstFetch[0].recoReason = 'Mutated Reason';

      // Second fetch (cache hit)
      final secondFetch = await service.getSimilar(100);
      expect(secondFetch.length, 1);
      // If it returned a clone, the cache hit object will NOT have the mutated reason
      expect(secondFetch[0].recoReason, isNull);
      expect(firstFetch[0] == secondFetch[0], isFalse);
    });

    test(
      'getWatchProviders should request and use the configured region',
      () async {
        final mockResponse = {
          'results': {
            'US': {
              'link': 'https://www.themoviedb.org/movie/123-us/watch',
              'flatrate': [
                {'provider_id': 8, 'provider_name': 'Netflix'},
              ],
            },
            'TR': {
              'link': 'https://www.themoviedb.org/movie/123-tr/watch',
              'flatrate': [
                {'provider_id': 337, 'provider_name': 'Disney Plus'},
              ],
            },
          },
        };

        final client = MockClient((request) async {
          expect(
            request.url.path.endsWith('/3/movie/123/watch/providers'),
            isTrue,
          );
          return http.Response(jsonEncode(mockResponse), 200);
        });

        // Construct with US region
        final service = TmdbService(client: client, region: 'US');
        final providers = await service.getWatchProviders(123);

        expect(providers.length, 1);
        expect(providers[0].name, 'Netflix');
        expect(providers[0].providerId, 8);
      },
    );
  });
}
