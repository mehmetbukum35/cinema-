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

  group('SocialApi request shaping', () {
    test('setupProfile sends is_public as an integer flag', () async {
      final api = apiWith(200, {'ok': true});

      await api.setupProfile('mehmet', true);
      expect(requests.last.url.path, '/api/social/profile/setup');
      expect(sentBody(), {'username': 'mehmet', 'is_public': 1});

      await api.setupProfile('mehmet', false);
      expect(sentBody()['is_public'], 0);
    });

    test(
      'registerDevice and unregisterDevice hit the device endpoints',
      () async {
        final api = apiWith(200, {'ok': true});

        await api.registerDevice('fcm-token', platform: 'android');
        expect(requests.last.url.path, '/api/social/device/register');
        expect(sentBody()['token'], 'fcm-token');
        expect(sentBody()['platform'], 'android');

        await api.unregisterDevice('fcm-token');
        expect(requests.last.url.path, '/api/social/device/unregister');
        expect(sentBody()['token'], 'fcm-token');
      },
    );

    test('reportReview sends is_tv as an integer flag', () async {
      final api = apiWith(200, {'auto_hidden': false});

      await api.reportReview(
        userId: 4,
        movieId: 550,
        isTV: true,
        reason: 'spam',
      );

      expect(sentBody(), {
        'user_id': 4,
        'movie_id': 550,
        'is_tv': 1,
        'reason': 'spam',
      });
    });

    test('activity feed encodes its cursor and passes the limit', () async {
      final api = apiWith(200, {'activity': <dynamic>[]});

      await api.getActivityFeedPage(
        friendId: 9,
        cursor: '2026-07-23 10:00:00+03',
        limit: 20,
      );

      final query = requests.last.url.query;
      expect(query, contains('friend_id=9'));
      expect(query, contains('limit=20'));
      expect(
        query,
        contains(Uri.encodeQueryComponent('2026-07-23 10:00:00+03')),
      );
      expect(query, isNot(contains('cursor=2026-07-23 10:00:00+03')));
    });

    test('an empty cursor is omitted entirely', () async {
      final api = apiWith(200, {'activity': <dynamic>[]});

      await api.getActivityFeedPage(cursor: '');

      expect(requests.last.url.query, isNot(contains('cursor=')));
    });
  });

  group('SocialApi response parsing', () {
    test('likeProfile parses a like count sent as a string', () async {
      // PHP tarafı sayıyı string olarak dönebiliyor; int.tryParse buna dayanmalı.
      final api = apiWith(200, {'like_count': '42'});

      expect(await api.likeProfile(3, true), 42);
    });

    test('likeProfile parses a like count sent as a number', () async {
      final api = apiWith(200, {'like_count': 7});

      expect(await api.likeProfile(3, true), 7);
    });

    test('likeProfile falls back to zero on a missing count', () async {
      final api = apiWith(200, <String, dynamic>{});

      expect(await api.likeProfile(3, false), 0);
    });

    test(
      'friend signals tolerate an empty PHP array instead of an object',
      () async {
        // PHP boş assoc dizisini `[]` olarak serialize eder; Map beklenen yerde
        // liste gelince boş sinyal kümesi sayılmalı, patlamamalı.
        final api = apiWith(200, {'signals': <dynamic>[]});

        final signals = await api.getFriendSignals();

        expect(signals.byTitleKey, isEmpty);
      },
    );

    test('friend signals map title keys to friend names', () async {
      final api = apiWith(200, {
        'signals': {
          'movie_550': ['Ada', 'Bora'],
          'tv_1399': ['Cem'],
          'bozuk_kayit': 'liste değil',
        },
      });

      final signals = await api.getFriendSignals();

      expect(signals.friendsFor(movieId: 550, isTv: false), ['Ada', 'Bora']);
      expect(signals.friendsFor(movieId: 1399, isTv: true), ['Cem']);
      expect(signals.byTitleKey.containsKey('bozuk_kayit'), isFalse);
    });

    test(
      'watchlist intersection returns empty when the payload is not a list',
      () async {
        final api = apiWith(200, {'watchlist': 'bozuk'});

        expect(await api.getWatchlistIntersection(5), isEmpty);
      },
    );

    test('reportReview reports whether the review was auto-hidden', () async {
      expect(
        await apiWith(200, {
          'auto_hidden': true,
        }).reportReview(userId: 1, movieId: 2, isTV: false, reason: 'spam'),
        isTrue,
      );
      expect(
        await apiWith(
          200,
          <String, dynamic>{},
        ).reportReview(userId: 1, movieId: 2, isTV: false, reason: 'spam'),
        isFalse,
      );
    });

    test('getBlockedUsers defaults to an empty list', () async {
      expect(
        await apiWith(200, <String, dynamic>{}).getBlockedUsers(),
        isEmpty,
      );
      expect(
        await apiWith(200, {
          'blocked': [
            {'id': 2},
          ],
        }).getBlockedUsers(),
        hasLength(1),
      );
    });
  });

  group('SocialApi error mapping', () {
    test(
      'every failing endpoint throws ApiException with the server code',
      () async {
        final cases = <String, Future<void> Function(ApiService)>{
          'setupProfile': (a) => a.setupProfile('x', true),
          'sendFriendRequest': (a) => a.sendFriendRequest('x'),
          'acceptFriendRequest': (a) => a.acceptFriendRequest(1),
          'rejectFriendRequest': (a) => a.rejectFriendRequest(1),
          'getActivityFeed': (a) => a.getActivityFeed(),
          'getWatchlistIntersection': (a) => a.getWatchlistIntersection(1),
          'getFriendSignals': (a) => a.getFriendSignals(),
          'getTopProfiles': (a) => a.getTopProfiles(),
          'likeProfile': (a) => a.likeProfile(1, true),
          'getTitleReviews': (a) => a.getTitleReviews('movie', 1),
          'blockUser': (a) => a.blockUser(1),
          'unblockUser': (a) => a.unblockUser(1),
          'getBlockedUsers': (a) => a.getBlockedUsers(),
          'registerDevice': (a) => a.registerDevice('t'),
          'unregisterDevice': (a) => a.unregisterDevice('t'),
          'reportReview': (a) =>
              a.reportReview(userId: 1, movieId: 1, isTV: false, reason: 'r'),
        };

        for (final entry in cases.entries) {
          final api = apiWith(400, {'error': 'hata', 'code': 'bad_request'});

          await expectLater(
            entry.value(api),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.statusCode, 'statusCode', 400)
                  .having((e) => e.code, 'code', 'bad_request'),
            ),
            reason: entry.key,
          );
        }
      },
    );

    test('a non-JSON error body still yields ApiException', () async {
      final api = apiWith(503, 'Service Unavailable');

      await expectLater(
        api.getTopProfiles(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });
  });

  group('SocialApi in-flight cache invalidation', () {
    test('a friend request drops the cached friends GET', () async {
      var friendsCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/social/friends') {
          friendsCalls++;
          return http.Response(
            jsonEncode({
              'friends': [],
              'pending_received': [],
              'pending_sent': [],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final api = ApiService(client: client);

      await api.getFriends();
      await api.sendFriendRequest('ada');
      await api.getFriends();

      // Mutasyon araya girdiği için ikinci GET paylaşılan uçuşu kullanamaz.
      expect(friendsCalls, 2);
    });
  });
}
