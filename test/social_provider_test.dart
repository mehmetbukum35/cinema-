import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/providers/social_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';

class MockApiService implements ApiService {
  Map<String, dynamic> friendsResponse = {
    'friends': [
      {'id': 10, 'username': 'testfriend'},
    ],
    'pending_received': [
      {'id': 20, 'username': 'pending_rec'},
    ],
    'pending_sent': [
      {'id': 30, 'username': 'pending_sent'},
    ],
  };

  List<dynamic> activityResponse = [
    {
      'movie_id': 101,
      'is_tv': 0,
      'rating': 3,
      'title': 'Test Movie',
      'poster_path': '/path.jpg',
      'updated_at': 1000,
      'friend_id': 10,
      'friend_name': 'Friend Name',
      'friend_username': 'testfriend',
    },
  ];

  List<dynamic> intersectionResponse = [
    {
      'id': 101,
      'is_tv': 0,
      'title': 'Common Movie',
      'poster_path': '/path.jpg',
      'backdrop_path': '/back.jpg',
      'overview': 'Common overview',
      'vote_average': 8.0,
      'release_date': '2026-01-01',
      'genre_ids': [28],
      'created_at': 1000,
      'updated_at': 1000,
      'deleted': 0,
    },
  ];

  Map<int, Map<String, dynamic>> tasteMatchResponses = {
    10: {
      'score': 78,
      'common_count': 5,
      'both_loved': 3,
      'agreement': 0.8,
      'genre_similarity': 0.7,
      'has_data': true,
    },
  };

  Map<String, dynamic> recommendationsResponse = {
    'recommendations': [
      {
        'id': 1,
        'movie_id': 603,
        'is_tv': 0,
        'title': 'The Matrix',
        'poster_path': '/matrix.jpg',
        'note': 'Mutlaka izle!',
        'seen': false,
        'created_at': 1000,
        'from_id': 10,
        'from_name': 'Friend Name',
        'from_username': 'testfriend',
      },
    ],
    'unseen': 1,
  };

  bool sendFriendRequestCalled = false;
  bool acceptFriendRequestCalled = false;
  bool rejectFriendRequestCalled = false;
  bool recommendCalled = false;
  bool markSeenCalled = false;
  int? recommendedFriendId;
  String? recommendedNote;
  int? loadedIntersectionFriendId;
  int? loadedActivityFriendId;

  @override
  Future<Map<String, dynamic>> getFriends() async => friendsResponse;

  @override
  Future<List<dynamic>> getActivityFeed({int? friendId}) async {
    loadedActivityFriendId = friendId;
    return activityResponse;
  }

  @override
  Future<List<dynamic>> getWatchlistIntersection(int friendId) async {
    loadedIntersectionFriendId = friendId;
    return intersectionResponse;
  }

  @override
  Future<Map<String, dynamic>> sendFriendRequest(String query) async {
    sendFriendRequestCalled = true;
    return {'ok': true};
  }

  @override
  Future<void> acceptFriendRequest(int friendId) async {
    acceptFriendRequestCalled = true;
  }

  @override
  Future<void> rejectFriendRequest(int friendId) async {
    rejectFriendRequestCalled = true;
  }

  @override
  Future<Map<String, dynamic>> getTasteMatch(int friendId) async {
    final res = tasteMatchResponses[friendId];
    if (res == null) {
      throw ApiException(statusCode: 404, message: 'not found');
    }
    return res;
  }

  @override
  Future<Map<String, dynamic>> getRecommendations() async =>
      recommendationsResponse;

  @override
  Future<void> markRecommendationsSeen() async {
    markSeenCalled = true;
  }

  @override
  Future<void> recommendToFriend({
    required int friendId,
    required int movieId,
    required bool isTv,
    required String title,
    String? posterPath,
    String? note,
  }) async {
    recommendCalled = true;
    recommendedFriendId = friendId;
    recommendedNote = note;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockApiService mockApi;
  late ProviderContainer container;

  setUp(() {
    mockApi = MockApiService();
    container = ProviderContainer(
      overrides: [
        socialProvider.overrideWith((ref) => SocialNotifier(mockApi, ref)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('SocialProvider Tests', () {
    test('loadFriends should update friends list state', () async {
      final notifier = container.read(socialProvider.notifier);

      expect(container.read(socialProvider).friends, isEmpty);
      expect(container.read(socialProvider).loading, isFalse);

      final future = notifier.loadFriends();
      expect(container.read(socialProvider).loading, isTrue);

      await future;

      final state = container.read(socialProvider);
      expect(state.loading, isFalse);
      expect(state.friends, hasLength(1));
      expect(state.friends[0]['username'], 'testfriend');
      expect(state.pendingReceived, hasLength(1));
      expect(state.pendingSent, hasLength(1));
    });

    test('loadActivityFeed should update activityFeed state', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadActivityFeed();

      final state = container.read(socialProvider);
      expect(state.activityFeed, hasLength(1));
      expect(state.activityFeed[0]['movie_id'], 101);
      expect(state.activityFeed[0]['friend_username'], 'testfriend');
    });

    test('sendFriendRequest should invoke API and reload friends', () async {
      final notifier = container.read(socialProvider.notifier);

      final success = await notifier.sendFriendRequest('query');

      expect(success, isTrue);
      expect(mockApi.sendFriendRequestCalled, isTrue);
      expect(
        container.read(socialProvider).friends,
        hasLength(1),
      ); // Loaded after request
    });

    test('acceptFriendRequest should invoke API and reload friends', () async {
      final notifier = container.read(socialProvider.notifier);

      final success = await notifier.acceptRequest(20);

      expect(success, isTrue);
      expect(mockApi.acceptFriendRequestCalled, isTrue);
      expect(container.read(socialProvider).friends, hasLength(1));
    });

    test('rejectFriendRequest should invoke API and reload friends', () async {
      final notifier = container.read(socialProvider.notifier);

      final success = await notifier.rejectRequest(20);

      expect(success, isTrue);
      expect(mockApi.rejectFriendRequestCalled, isTrue);
      expect(container.read(socialProvider).friends, hasLength(1));
    });

    test('loadFriends should also populate taste scores', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadFriends();
      // loadTasteScores await edilmeden tetiklenir; tamamlanmasını bekle.
      await Future<void>.delayed(Duration.zero);

      final state = container.read(socialProvider);
      expect(state.tasteScores[10], 78);
    });

    test('loadTasteScores should skip friends without data', () async {
      mockApi.friendsResponse = {
        'friends': [
          {'id': 10, 'username': 'testfriend'},
          {'id': 99, 'username': 'nodata'}, // mock 404 döner
        ],
        'pending_received': [],
        'pending_sent': [],
      };
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadFriends();
      await notifier.loadTasteScores();

      final state = container.read(socialProvider);
      expect(state.tasteScores[10], 78);
      expect(state.tasteScores.containsKey(99), isFalse);
    });

    test('loadRecommendations should update inbox and unseen count', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadRecommendations();

      final state = container.read(socialProvider);
      expect(state.recommendations, hasLength(1));
      expect(state.recommendations[0]['title'], 'The Matrix');
      expect(state.unseenRecommendations, 1);
    });

    test(
      'markRecommendationsSeen should zero the counter and call API',
      () async {
        final notifier = container.read(socialProvider.notifier);
        await notifier.loadRecommendations();

        await notifier.markRecommendationsSeen();

        expect(container.read(socialProvider).unseenRecommendations, 0);
        expect(mockApi.markSeenCalled, isTrue);
      },
    );

    test('markRecommendationsSeen is a no-op when nothing is unseen', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.markRecommendationsSeen();

      expect(mockApi.markSeenCalled, isFalse);
    });

    test('recommendToFriend should pass movie and note to API', () async {
      final notifier = container.read(socialProvider.notifier);
      final movie = Movie(
        id: 603,
        title: 'The Matrix',
        posterPath: '/matrix.jpg',
        overview: '',
        voteAverage: 8.7,
      );

      final ok = await notifier.recommendToFriend(
        friendId: 10,
        movie: movie,
        note: 'Mutlaka izle!',
      );

      expect(ok, isTrue);
      expect(mockApi.recommendCalled, isTrue);
      expect(mockApi.recommendedFriendId, 10);
      expect(mockApi.recommendedNote, 'Mutlaka izle!');
    });

    test(
      'loadWatchlistIntersection should fetch and map movies to intersection list',
      () async {
        final notifier = container.read(socialProvider.notifier);

        await notifier.loadWatchlistIntersection(10);

        expect(mockApi.loadedIntersectionFriendId, 10);
        final state = container.read(socialProvider);
        expect(state.intersection, hasLength(1));
        expect(state.intersection[0].id, 101);
        expect(state.intersection[0].title, 'Common Movie');
      },
    );

    test(
      'loadFriendActivity should fetch and update friendActivities cache',
      () async {
        final notifier = container.read(socialProvider.notifier);

        expect(container.read(socialProvider).friendActivities[10], isNull);

        await notifier.loadFriendActivity(10);

        expect(mockApi.loadedActivityFriendId, 10);
        final state = container.read(socialProvider);
        expect(state.friendActivities[10], hasLength(1));
        expect(state.friendActivities[10]![0]['movie_id'], 101);
        expect(state.friendActivities[10]![0]['friend_username'], 'testfriend');
      },
    );
  });
}
