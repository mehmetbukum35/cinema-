import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/social.dart';

void main() {
  group('FriendSignals', () {
    test('fromJson parses title keys and friend names', () {
      final signals = FriendSignals.fromJson({
        'movie_101': ['Alice', 'Bob'],
        'tv_202': ['Carol'],
      });

      expect(signals.friendsFor(movieId: 101, isTv: false), ['Alice', 'Bob']);
      expect(signals.friendsFor(movieId: 202, isTv: true), ['Carol']);
      expect(signals.friendsFor(movieId: 999, isTv: false), isNull);
    });

    test('toRecommendationMap returns engine-compatible map', () {
      const signals = FriendSignals({'movie_5': ['Dave']});
      expect(signals.toRecommendationMap(), {'movie_5': ['Dave']});
    });
  });
}
