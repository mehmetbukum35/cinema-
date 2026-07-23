import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  late List<http.Request> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsService.activeLanguageCode = 'tr';
    await PrefsService.saveTokens(accessToken: 'a', refreshToken: 'r');
    await PrefsService.saveUserData({'id': 1});
    requests = [];
  });

  ApiService apiWith(int status, Object? body) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return ApiService(client: client);
  }

  Map<String, dynamic> sentBody() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;

  const session = {'id': 3, 'status': 'voting', 'deck': <dynamic>[]};

  group('CouchApi happy paths', () {
    test('createCouchSession posts the friend and deck', () async {
      final api = apiWith(200, {'session': session});

      final res = await api.createCouchSession(
        friendId: 12,
        deck: [
          {'movie_id': 550, 'is_tv': 0},
        ],
      );

      expect(requests.last.url.path, '/api/social/couch/create');
      expect(sentBody()['friend_id'], 12);
      expect((sentBody()['deck'] as List).single, {
        'movie_id': 550,
        'is_tv': 0,
      });
      expect(res['id'], 3);
    });

    test('getCouchSession loads a session by id', () async {
      final api = apiWith(200, {'session': session});

      final res = await api.getCouchSession(3);

      expect(requests.last.url.path, '/api/social/couch/3');
      expect(res['status'], 'voting');
    });

    test(
      'voteCouchSession sends is_tv as an integer and liked as a bool',
      () async {
        final api = apiWith(200, {'session': session});

        await api.voteCouchSession(
          sessionId: 3,
          movieId: 550,
          isTv: true,
          liked: false,
        );

        expect(requests.last.url.path, '/api/social/couch/3/vote');
        expect(sentBody(), {'movie_id': 550, 'is_tv': 1, 'liked': false});
      },
    );

    test('cancelCouchSession posts to the cancel endpoint', () async {
      final api = apiWith(200, {'ok': true});

      await api.cancelCouchSession(3);

      expect(requests.last.url.path, '/api/social/couch/3/cancel');
      expect(requests.last.method, 'POST');
    });

    test('getUsedCouchMovies stringifies whatever the server sends', () async {
      final api = apiWith(200, {
        'used_keys': ['movie_550', 'tv_1399', 42],
      });

      expect(await api.getUsedCouchMovies(12), ['movie_550', 'tv_1399', '42']);
      expect(requests.last.url.query, contains('friend_id=12'));
    });

    test('getUsedCouchMovies defaults to empty', () async {
      expect(
        await apiWith(200, <String, dynamic>{}).getUsedCouchMovies(12),
        isEmpty,
      );
    });
  });

  group('CouchApi active session', () {
    test('returns null when there is no active session', () async {
      final api = apiWith(200, {'session': null});

      expect(await api.getActiveCouchSession(), isNull);
    });

    test('returns null when the key is absent entirely', () async {
      final api = apiWith(200, <String, dynamic>{});

      expect(await api.getActiveCouchSession(), isNull);
    });

    test('returns the session when one is live', () async {
      final api = apiWith(200, {'session': session});

      expect((await api.getActiveCouchSession())!['id'], 3);
    });

    test('a malformed session is a 502, not a null session', () async {
      // Boş oturum ile bozuk gövde ayırt edilmeli; ikincisi sessizce
      // "aktif oturum yok" sayılırsa canlı oturum kaybolur.
      final api = apiWith(200, {'session': 'bozuk'});

      await expectLater(
        api.getActiveCouchSession(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502),
        ),
      );
    });
  });

  group('CouchApi error mapping', () {
    test('a session-shaped endpoint rejects a malformed payload', () async {
      final cases = <String, Future<void> Function(ApiService)>{
        'createCouchSession': (a) =>
            a.createCouchSession(friendId: 1, deck: []),
        'getCouchSession': (a) => a.getCouchSession(3),
        'voteCouchSession': (a) => a.voteCouchSession(
          sessionId: 3,
          movieId: 1,
          isTv: false,
          liked: true,
        ),
      };

      for (final entry in cases.entries) {
        final api = apiWith(200, {'session': 'bozuk'});

        await expectLater(
          entry.value(api),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502),
          ),
          reason: entry.key,
        );
      }
    });

    test(
      'every failing endpoint throws ApiException with the server code',
      () async {
        final cases = <String, Future<void> Function(ApiService)>{
          'createCouchSession': (a) =>
              a.createCouchSession(friendId: 1, deck: []),
          'getActiveCouchSession': (a) => a.getActiveCouchSession(),
          'getCouchSession': (a) => a.getCouchSession(3),
          'voteCouchSession': (a) => a.voteCouchSession(
            sessionId: 3,
            movieId: 1,
            isTv: false,
            liked: true,
          ),
          'cancelCouchSession': (a) => a.cancelCouchSession(3),
          'getUsedCouchMovies': (a) => a.getUsedCouchMovies(1),
        };

        for (final entry in cases.entries) {
          final api = apiWith(409, {
            'error': 'meşgul',
            'code': 'session_active',
          });

          await expectLater(
            entry.value(api),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.statusCode, 'statusCode', 409)
                  .having((e) => e.code, 'code', 'session_active'),
            ),
            reason: entry.key,
          );
        }
      },
    );
  });
}
