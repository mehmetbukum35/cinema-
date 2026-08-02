import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/notification_service.dart';

void main() {
  group('NotificationService.payloadFromData', () {
    test('builds couch invite payload with session_id', () {
      expect(
        NotificationService.payloadFromData({
          'type': 'couch_invite',
          'session_id': '42',
        }),
        'couch_invite|42',
      );
    });

    test('builds couch match payload with session_id', () {
      expect(
        NotificationService.payloadFromData({
          'type': 'couch_match',
          'session_id': '7',
        }),
        'couch_match|7',
      );
    });

    test('returns null when couch payload lacks session_id', () {
      expect(
        NotificationService.payloadFromData({'type': 'couch_invite'}),
        isNull,
      );
    });

    test('builds friend request payload without movie fields', () {
      expect(
        NotificationService.payloadFromData({'type': 'friend_request'}),
        'friend_request',
      );
    });

    test('builds movie recommendation payload', () {
      expect(
        NotificationService.payloadFromData({
          'type': 'friend_recommend',
          'movie_id': '550',
          'is_tv': '0',
        }),
        'friend_recommend|550|0',
      );
    });

    test('returns null when the data carries no type', () {
      expect(NotificationService.payloadFromData({}), isNull);
      expect(NotificationService.payloadFromData({'type': ''}), isNull);
      expect(NotificationService.payloadFromData({'movie_id': '550'}), isNull);
    });

    test('returns null when couch match payload lacks session_id', () {
      expect(
        NotificationService.payloadFromData({'type': 'couch_match'}),
        isNull,
      );
    });

    test('accepts the legacy isTV key as an is_tv fallback', () {
      expect(
        NotificationService.payloadFromData({
          'type': 'release',
          'movie_id': '550',
          'isTV': '1',
        }),
        'release|550|1',
      );
    });

    test('coerces non-string ids sent by the backend', () {
      expect(
        NotificationService.payloadFromData({
          'type': 'release',
          'movie_id': 550,
          'is_tv': true,
        }),
        'release|550|true',
      );
      expect(
        NotificationService.payloadFromData({
          'type': 'couch_invite',
          'session_id': 42,
        }),
        'couch_invite|42',
      );
    });
  });

  group('NotificationService.routeForPayload', () {
    test('ignores an absent or empty payload', () {
      expect(NotificationService.routeForPayload(null), isNull);
      expect(NotificationService.routeForPayload(''), isNull);
    });

    test('sends friendship notifications to their social tab', () {
      expect(NotificationService.routeForPayload('friend_request'), (
        socialTab: 1,
        couch: false,
        movieId: null,
        isTV: false,
      ));
      expect(NotificationService.routeForPayload('friend_accept'), (
        socialTab: 0,
        couch: false,
        movieId: null,
        isTV: false,
      ));
    });

    test('sends both couch notification types to the couch screen', () {
      const couchRoute = (
        socialTab: null,
        couch: true,
        movieId: null,
        isTV: false,
      );
      expect(
        NotificationService.routeForPayload('couch_invite|42'),
        couchRoute,
      );
      expect(NotificationService.routeForPayload('couch_match|7'), couchRoute);
    });

    test('opens movie detail for every recommendation type', () {
      for (final type in const [
        'release',
        'movie_recommend',
        'recommendation',
        'movie_recommendation',
        'friend_recommend',
      ]) {
        expect(
          NotificationService.routeForPayload('$type|550|0'),
          (socialTab: null, couch: false, movieId: 550, isTV: false),
          reason: '$type should deep-link into movie detail',
        );
      }
    });

    test('treats both 1 and true as a TV title', () {
      expect(
        NotificationService.routeForPayload('release|1399|1')?.isTV,
        isTrue,
      );
      expect(
        NotificationService.routeForPayload('release|1399|true')?.isTV,
        isTrue,
      );
      expect(
        NotificationService.routeForPayload('release|1399|0')?.isTV,
        isFalse,
      );
      // Beklenmeyen bir değer film olarak yorumlanır (TV'ye kaymaz).
      expect(
        NotificationService.routeForPayload('release|1399|yes')?.isTV,
        isFalse,
      );
    });

    test('drops a deep link that is missing the is_tv segment', () {
      expect(NotificationService.routeForPayload('release'), isNull);
      expect(NotificationService.routeForPayload('release|550'), isNull);
    });

    test('drops a deep link whose movie id is unusable', () {
      expect(NotificationService.routeForPayload('release|0|0'), isNull);
      expect(NotificationService.routeForPayload('release|abc|0'), isNull);
      expect(NotificationService.routeForPayload('release||0'), isNull);
    });

    test('ignores notification types that have no destination', () {
      expect(NotificationService.routeForPayload('unknown_type|550|0'), isNull);
      expect(NotificationService.routeForPayload('digest'), isNull);
    });
  });

  group('NotificationService.socialTabForNotificationType', () {
    test('opens Requests for a new friend request', () {
      expect(
        NotificationService.socialTabForNotificationType('friend_request'),
        1,
      );
    });

    test('opens Friends after a request is accepted', () {
      expect(
        NotificationService.socialTabForNotificationType('friend_accept'),
        0,
      );
    });

    test('ignores notification types outside the social tabs', () {
      expect(
        NotificationService.socialTabForNotificationType('release'),
        isNull,
      );
    });
  });

  group('notification detail locale', () {
    test('uses Turkish TMDB locale for Turkish UI', () {
      final locale = NotificationService.notificationContentLocale('tr');
      expect(locale.language, 'tr-TR');
      expect(locale.region, 'TR');
    });

    test('uses English TMDB locale for English and unknown UI locales', () {
      final english = NotificationService.notificationContentLocale('en');
      final fallback = NotificationService.notificationContentLocale('de');
      expect(english, (language: 'en-US', region: 'US'));
      expect(fallback, (language: 'en-US', region: 'US'));
    });
  });

  group('cold-start notification routing', () {
    test(
      'routes only one payload when remote and local launch data coexist',
      () {
        expect(
          NotificationService.selectInitialPayload(
            remote: 'friend_request',
            local: 'release|550|0',
          ),
          'friend_request',
        );
        expect(
          NotificationService.selectInitialPayload(
            remote: null,
            local: 'release|550|0',
          ),
          'release|550|0',
        );
      },
    );

    test('retries while the navigator is still starting', () {
      expect(
        NotificationService.shouldRetryInitialRoute(
          navigatorReady: false,
          attempt: 3,
          maxAttempts: 10,
        ),
        isTrue,
      );
    });

    test('stops retrying when ready or when the retry budget expires', () {
      expect(
        NotificationService.shouldRetryInitialRoute(
          navigatorReady: true,
          attempt: 3,
          maxAttempts: 10,
        ),
        isFalse,
      );
      expect(
        NotificationService.shouldRetryInitialRoute(
          navigatorReady: false,
          attempt: 10,
          maxAttempts: 10,
        ),
        isFalse,
      );
    });
  });
}
