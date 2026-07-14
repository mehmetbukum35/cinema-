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
}
