import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsService.activeLanguageCode = 'tr';
    await PrefsService.saveTokens(
      accessToken: 'initial_access',
      refreshToken: 'initial_refresh',
    );
  });

  group('ApiService Tests', () {
    test('login should send correct payload and return response', () async {
      // 1. Arrange: Setup Mock Client
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/login');

        final body = jsonDecode(request.body);
        expect(body['email'], 'test@example.com');
        expect(body['password'], 'secret123');

        return http.Response(
          jsonEncode({
            'tokens': {
              'access_token': 'new_access',
              'refresh_token': 'new_refresh',
            },
            'user': {
              'id': 1,
              'email': 'test@example.com',
              'username': 'testuser',
              'display_name': 'Test User',
              'is_public': 1,
            },
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);

      // 2. Act
      final user = await apiService.login(
        email: 'test@example.com',
        password: 'secret123',
      );

      // 3. Assert
      expect(user, isNotNull);
      expect(user['user'], isNotNull);
      expect(user['user']['id'], 1);
      expect(user['user']['username'], 'testuser');
    });

    test('loginWithGoogle should post id_token and return session', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/google');
        final body = jsonDecode(request.body);
        expect(body['id_token'], 'google-id-token-x');

        return http.Response(
          jsonEncode({
            'user': {
              'id': 7,
              'email': 'ali@example.com',
              'display_name': 'Ali',
              'username': null,
            },
            'tokens': {'access_token': 'acc', 'refresh_token': 'ref'},
            'is_new': true,
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);
      final res = await apiService.loginWithGoogle('google-id-token-x');

      expect(res['user']['id'], 7);
      expect(res['tokens']['access_token'], 'acc');
      expect(res['is_new'], isTrue);
    });

    test(
      'loginWithGoogle should throw ApiException with server error',
      () async {
        // Not: MockClient content-type başlıksız cevabı Latin-1 encode eder;
        // Türkçe karakter kullanma.
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'Google auth failed.'}),
            401,
          );
        });

        final apiService = ApiService(client: mockClient);
        expect(
          () => apiService.loginWithGoogle('bogus'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
          ),
        );
      },
    );

    test('getFriends should send GET with Auth header', () async {
      // 1. Arrange: Setup Mock Client
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/social/friends');
        expect(request.headers['Authorization'], 'Bearer initial_access');

        return http.Response(
          jsonEncode({
            'friends': [
              {'id': 2, 'username': 'friend1'},
            ],
            'pending_received': [],
            'pending_sent': [],
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);

      // 2. Act
      final res = await apiService.getFriends();

      // 3. Assert
      expect(res['friends'], hasLength(1));
      expect(res['friends'][0]['username'], 'friend1');
    });

    test('should throw ApiException on HTTP 400', () async {
      // 1. Arrange
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid credentials'}),
          400,
        );
      });

      final apiService = ApiService(client: mockClient);

      // 2. Act & Assert
      expect(
        () => apiService.login(email: 'test@example.com', password: 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Giriş başarısız.',
          ),
        ),
      );
    });

    test(
      'should throw ApiException on HTTP 400 with empty JSON body',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response('', 400);
        });

        final apiService = ApiService(client: mockClient);

        expect(
          () => apiService.login(email: 'test@example.com', password: 'wrong'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Giriş başarısız.',
            ),
          ),
        );
      },
    );

    test('should automatically refresh token on 401', () async {
      int requestCount = 0;

      // 1. Arrange: Mock client handles:
      // - First request returns 401
      // - Token refresh POST returns new tokens nested under 'tokens'
      // - Second request (retried) succeeds with new token
      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          expect(request.url.path, '/api/social/friends');
          expect(request.headers['Authorization'], 'Bearer initial_access');
          return http.Response('Unauthorized', 401);
        } else if (requestCount == 2) {
          expect(request.url.path, '/api/auth/refresh');
          final body = jsonDecode(request.body);
          expect(body['refresh_token'], 'initial_refresh');
          return http.Response(
            jsonEncode({
              'tokens': {
                'access_token': 'refreshed_access',
                'refresh_token': 'refreshed_refresh',
              },
            }),
            200,
          );
        } else {
          expect(request.url.path, '/api/social/friends');
          expect(request.headers['Authorization'], 'Bearer refreshed_access');
          return http.Response(
            jsonEncode({
              'friends': [],
              'pending_received': [],
              'pending_sent': [],
            }),
            200,
          );
        }
      });

      final apiService = ApiService(client: mockClient);

      // 2. Act
      final res = await apiService.getFriends();

      // 3. Assert
      expect(res, isNotNull);
      expect(requestCount, 3); // 1 original + 1 refresh + 1 retry
      expect(await PrefsService.getAccessToken(), 'refreshed_access');
      expect(await PrefsService.getRefreshToken(), 'refreshed_refresh');
    });

    test('getTasteMatch should call taste endpoint and parse score', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/social/match/taste/42');
        expect(request.headers['Authorization'], 'Bearer initial_access');
        return http.Response(
          jsonEncode({
            'score': 78,
            'common_count': 5,
            'both_loved': 3,
            'agreement': 0.8,
            'genre_similarity': 0.7,
            'has_data': true,
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);
      final res = await apiService.getTasteMatch(42);

      expect(res['score'], 78);
      expect(res['has_data'], isTrue);
    });

    test('getSentRecommendations should parse sent payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/social/recommendations/sent');
        return http.Response(
          jsonEncode({
            'sent': [
              {
                'id': 1,
                'movie_id': 603,
                'is_tv': 0,
                'title': 'The Matrix',
                'created_at': 1000,
                'to_id': 2,
                'to_name': 'Bob',
                'to_username': 'bob',
              },
            ],
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);
      final res = await apiService.getSentRecommendations();

      expect(res['sent'], hasLength(1));
      expect(res['sent'][0]['title'], 'The Matrix');
      expect(res['sent'][0]['to_username'], 'bob');
    });

    test('recommendToFriend should POST correct payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/social/recommend');

        final body = jsonDecode(request.body);
        expect(body['friend_id'], 42);
        expect(body['movie_id'], 603);
        expect(body['is_tv'], 0);
        expect(body['title'], 'The Matrix');
        expect(body['note'], 'Mutlaka izle!');

        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final apiService = ApiService(client: mockClient);
      await apiService.recommendToFriend(
        friendId: 42,
        movieId: 603,
        isTv: false,
        title: 'The Matrix',
        note: 'Mutlaka izle!',
      );
    });

    test('getRecommendations should parse inbox payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/social/recommendations');
        return http.Response(
          jsonEncode({
            'recommendations': [
              {
                'id': 1,
                'movie_id': 603,
                'is_tv': 0,
                'title': 'The Matrix',
                'seen': false,
                'from_username': 'alice',
              },
            ],
            'unseen': 1,
          }),
          200,
        );
      });

      final apiService = ApiService(client: mockClient);
      final res = await apiService.getRecommendations();

      expect(res['recommendations'], hasLength(1));
      expect(res['unseen'], 1);
    });

    test(
      'getTitleScore should call score endpoint and parse payload',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/titles/movie/603/score');
          expect(request.headers['Authorization'], 'Bearer initial_access');
          return http.Response(
            jsonEncode({
              'total': 12,
              'liked_percent': 83,
              'enough': true,
              'threshold': 5,
              'distribution': {'harika': 6, 'iyi': 4, 'eh': 1, 'berbat': 1},
            }),
            200,
          );
        });

        final apiService = ApiService(client: mockClient);
        final res = await apiService.getTitleScore('movie', 603);

        expect(res['total'], 12);
        expect(res['liked_percent'], 83);
        expect(res['enough'], isTrue);
      },
    );

    test('should throw auth_err_rate_limited on HTTP 429', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.',
          }),
          429,
        );
      });

      final apiService = ApiService(client: mockClient);
      expect(
        () => apiService.getFriends(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', 'auth_err_rate_limited'),
        ),
      );
    });
  });
}
