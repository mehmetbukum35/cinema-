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
