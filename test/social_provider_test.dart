import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/providers/social_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';

class MockApiService implements ApiService {
  final List<Completer<Map<String, dynamic>>> friendsRequests = [];
  final List<Completer<Map<String, dynamic>>> sentRecommendationRequests = [];
  final List<Completer<ActivityFeedPage>> friendActivityRequests = [];
  final List<Completer<ActivityFeedPage>> activityRequests = [];
  final List<Completer<List<dynamic>>> intersectionRequests = [];
  final List<Completer<Map<String, dynamic>>> recommendationsRequests = [];
  final List<Completer<Map<String, dynamic>>> receivedPageRequests = [];
  final List<Completer<Map<String, dynamic>>> sentPageRequests = [];
  final List<Completer<int>> profileLikeRequests = [];
  final List<bool> profileLikeValues = [];
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

  Map<String, dynamic> sentRecommendationsResponse = {
    'sent': [
      {
        'id': 2,
        'movie_id': 550,
        'is_tv': 0,
        'title': 'Fight Club',
        'poster_path': '/fc.jpg',
        'created_at': 2000,
        'to_id': 10,
        'to_name': 'Friend Name',
        'to_username': 'testfriend',
      },
    ],
  };

  bool sendFriendRequestCalled = false;
  bool acceptFriendRequestCalled = false;
  bool rejectFriendRequestCalled = false;
  bool recommendCalled = false;
  bool markSeenCalled = false;
  int? deletedRecommendationId;
  int? recommendedFriendId;
  String? recommendedNote;
  int? loadedIntersectionFriendId;
  int? loadedActivityFriendId;
  bool paginateActivity = false;
  bool markSeenShouldFail = false;

  @override
  Future<Map<String, dynamic>> getFriends() async {
    if (friendsRequests.isNotEmpty) {
      return friendsRequests.removeAt(0).future;
    }
    return friendsResponse;
  }

  @override
  Future<List<dynamic>> getActivityFeed({int? friendId}) async {
    loadedActivityFriendId = friendId;
    return activityResponse;
  }

  @override
  Future<ActivityFeedPage> getActivityFeedPage({
    int? friendId,
    String? cursor,
    int limit = 50,
  }) async {
    loadedActivityFriendId = friendId;
    if (friendId != null && friendActivityRequests.isNotEmpty) {
      return friendActivityRequests.removeAt(0).future;
    }
    if (friendId == null && activityRequests.isNotEmpty) {
      return activityRequests.removeAt(0).future;
    }
    if (paginateActivity && cursor == 'page-2') {
      final second = Map<String, dynamic>.from(
        activityResponse.single as Map<String, dynamic>,
      )..['movie_id'] = 202;
      return ActivityFeedPage(items: [second], hasMore: false);
    }
    return ActivityFeedPage(
      items: activityResponse,
      nextCursor: paginateActivity ? 'page-2' : null,
      hasMore: paginateActivity,
    );
  }

  @override
  Future<List<dynamic>> getWatchlistIntersection(int friendId) async {
    loadedIntersectionFriendId = friendId;
    if (intersectionRequests.isNotEmpty) {
      return intersectionRequests.removeAt(0).future;
    }
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

  /// true → eski sunucu simülasyonu: taste-all 404 döner, tekil uca düşülür.
  bool allTasteMatchesUnsupported = false;
  bool allTasteMatchesCalled = false;

  @override
  Future<List<dynamic>> getAllTasteMatches() async {
    allTasteMatchesCalled = true;
    if (allTasteMatchesUnsupported) {
      throw ApiException(statusCode: 404, message: 'Bilinmeyen uç');
    }
    return [
      for (final e in tasteMatchResponses.entries)
        {'friend_id': e.key, ...e.value},
    ];
  }

  @override
  Future<Map<String, dynamic>> getRecommendations() async {
    if (recommendationsRequests.isNotEmpty) {
      return recommendationsRequests.removeAt(0).future;
    }
    return recommendationsResponse;
  }

  @override
  Future<Map<String, dynamic>> getSentRecommendations() async {
    if (sentRecommendationRequests.isNotEmpty) {
      return sentRecommendationRequests.removeAt(0).future;
    }
    return sentRecommendationsResponse;
  }

  @override
  Future<Map<String, dynamic>> getRecommendationsPage({
    required String cursor,
    int limit = 30,
  }) async {
    if (receivedPageRequests.isNotEmpty) {
      return receivedPageRequests.removeAt(0).future;
    }
    return {
      'recommendations': [
        {
          'id': 3,
          'movie_id': 777,
          'is_tv': 1,
          'title': 'Page Two',
          'seen': true,
          'created_at': 500,
          'from_id': 10,
          'from_username': 'testfriend',
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getSentRecommendationsPage({
    required String cursor,
    int limit = 30,
  }) async {
    if (sentPageRequests.isNotEmpty) {
      return sentPageRequests.removeAt(0).future;
    }
    return {
      'sent': [
        {
          'id': 4,
          'movie_id': 778,
          'is_tv': 0,
          'title': 'Sent Page Two',
          'created_at': 400,
          'to_id': 10,
          'to_username': 'testfriend',
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<void> markRecommendationsSeen() async {
    markSeenCalled = true;
    if (markSeenShouldFail) throw Exception('mark seen failed');
  }

  @override
  Future<void> deleteRecommendation(int recommendationId) async {
    deletedRecommendationId = recommendationId;
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
  Future<Map<String, dynamic>> getTopProfiles() async => {
    'profiles': [
      {
        'id': 42,
        'username': 'popular',
        'like_count': 0,
        'me_liked': false,
        'is_me': false,
        'liked_titles': 5,
        'previews': [],
      },
    ],
  };

  @override
  Future<int> likeProfile(int ownerId, bool liked) async {
    profileLikeValues.add(liked);
    return profileLikeRequests.removeAt(0).future;
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
      expect(state.friends[0].username, 'testfriend');
      expect(state.pendingReceived, hasLength(1));
      expect(state.pendingSent, hasLength(1));
    });

    test('older friends response cannot overwrite a newer refresh', () async {
      final stale = Completer<Map<String, dynamic>>();
      final fresh = Completer<Map<String, dynamic>>();
      mockApi.friendsRequests.addAll([stale, fresh]);
      final notifier = container.read(socialProvider.notifier);

      final staleLoad = notifier.loadFriends();
      final freshLoad = notifier.loadFriends();
      fresh.complete({
        'friends': [
          {'id': 11, 'username': 'fresh_friend'},
        ],
        'pending_received': [],
        'pending_sent': [],
      });
      await freshLoad;
      stale.complete({
        'friends': [
          {'id': 10, 'username': 'stale_friend'},
        ],
        'pending_received': [],
        'pending_sent': [],
      });
      await staleLoad;

      expect(container.read(socialProvider).friends.single.id, 11);
      expect(container.read(socialProvider).loading, isFalse);
    });

    test('loadFriends exits safely after provider disposal', () async {
      final pending = Completer<Map<String, dynamic>>();
      mockApi.friendsRequests.add(pending);
      final notifier = container.read(socialProvider.notifier);
      final load = notifier.loadFriends();

      container.dispose();
      pending.complete({
        'friends': [],
        'pending_received': [],
        'pending_sent': [],
      });

      await expectLater(load, completes);
      container = ProviderContainer();
    });

    test('loadActivityFeed should update activityFeed state', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadActivityFeed();

      final state = container.read(socialProvider);
      expect(state.activityFeed, hasLength(1));
      expect(state.activityFeed[0].movieId, 101);
      expect(state.activityFeed[0].friendUsername, 'testfriend');
    });

    test('loadMoreActivityFeed should append the cursor page', () async {
      final notifier = container.read(socialProvider.notifier);
      mockApi.paginateActivity = true;

      await notifier.loadActivityFeed();
      await notifier.loadMoreActivityFeed();

      final state = container.read(socialProvider);
      expect(state.activityFeed, hasLength(2));
      expect(state.activityFeed.last.movieId, 202);
      expect(state.activityHasMore, isFalse);
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

    test(
      'loadTasteScores should fall back to per-friend calls on old server (404)',
      () async {
        mockApi.allTasteMatchesUnsupported = true;
        final notifier = container.read(socialProvider.notifier);

        await notifier.loadFriends();
        await notifier.loadTasteScores();

        final state = container.read(socialProvider);
        expect(mockApi.allTasteMatchesCalled, isTrue);
        expect(state.tasteScores[10], 78); // tekil uçtan geldi
      },
    );

    test('loadRecommendations should update inbox and unseen count', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadRecommendations();

      final state = container.read(socialProvider);
      expect(state.recommendations, hasLength(1));
      expect(state.recommendations[0].title, 'The Matrix');
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

    test('loadSentRecommendations should map sent items', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadSentRecommendations();

      final state = container.read(socialProvider);
      expect(state.sentRecommendations, hasLength(1));
      expect(state.sentRecommendations[0].title, 'Fight Club');
      expect(state.sentRecommendations[0].toUsername, 'testfriend');
    });

    test(
      'older sent recommendations cannot overwrite a newer refresh',
      () async {
        final stale = Completer<Map<String, dynamic>>();
        final fresh = Completer<Map<String, dynamic>>();
        mockApi.sentRecommendationRequests.addAll([stale, fresh]);
        final notifier = container.read(socialProvider.notifier);

        final staleLoad = notifier.loadSentRecommendations();
        final freshLoad = notifier.loadSentRecommendations();
        fresh.complete({
          'sent': [
            {
              'id': 20,
              'movie_id': 20,
              'is_tv': 0,
              'title': 'Fresh',
              'created_at': 20,
              'to_id': 10,
            },
          ],
        });
        await freshLoad;
        stale.complete({
          'sent': [
            {
              'id': 10,
              'movie_id': 10,
              'is_tv': 0,
              'title': 'Stale',
              'created_at': 10,
              'to_id': 10,
            },
          ],
        });
        await staleLoad;

        expect(
          container.read(socialProvider).sentRecommendations.single.id,
          20,
        );
      },
    );

    test('loadReceivedRecommendations should map received items', () async {
      final notifier = container.read(socialProvider.notifier);

      await notifier.loadReceivedRecommendations();

      final state = container.read(socialProvider);
      expect(state.receivedRecommendations, hasLength(1));
      expect(state.receivedRecommendations[0].title, 'The Matrix');
      expect(state.receivedRecommendations[0].fromUsername, 'testfriend');
    });

    test('deleteRecommendation removes the item from local lists', () async {
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadSentRecommendations();
      await notifier.loadReceivedRecommendations();

      final deleted = await notifier.deleteRecommendation(2);

      expect(deleted, isTrue);
      expect(mockApi.deletedRecommendationId, 2);
      expect(container.read(socialProvider).sentRecommendations, isEmpty);
      expect(
        container.read(socialProvider).receivedRecommendations,
        hasLength(1),
      );
    });

    test('deleteRecommendation decrements unseen inbox count', () async {
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadRecommendations();

      await notifier.deleteRecommendation(1);

      expect(container.read(socialProvider).unseenRecommendations, 0);
    });

    test('loadMoreReceivedRecommendations appends the next page', () async {
      mockApi.recommendationsResponse['next_cursor'] = 'page-2';
      mockApi.recommendationsResponse['has_more'] = true;
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadReceivedRecommendations();

      await notifier.loadMoreReceivedRecommendations();

      final state = container.read(socialProvider);
      expect(state.receivedRecommendations, hasLength(2));
      expect(state.receivedRecommendations.last.title, 'Page Two');
      expect(state.receivedRecommendationsHasMore, isFalse);
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
        expect(state.friendActivities[10]![0].movieId, 101);
        expect(state.friendActivities[10]![0].friendUsername, 'testfriend');
      },
    );

    test(
      'older friend activity cannot overwrite a newer friend view',
      () async {
        final stale = Completer<ActivityFeedPage>();
        final fresh = Completer<ActivityFeedPage>();
        mockApi.friendActivityRequests.addAll([stale, fresh]);
        final notifier = container.read(socialProvider.notifier);

        final first = notifier.loadFriendActivity(10);
        final second = notifier.loadFriendActivity(20);
        fresh.complete(
          const ActivityFeedPage(
            items: [],
            nextCursor: 'friend-20',
            hasMore: true,
          ),
        );
        await second;
        stale.complete(
          const ActivityFeedPage(
            items: [],
            nextCursor: 'friend-10',
            hasMore: true,
          ),
        );
        await first;

        final state = container.read(socialProvider);
        expect(state.friendActivityFriendId, 20);
        expect(state.friendActivityCursor, 'friend-20');
        expect(state.friendActivities.containsKey(10), isFalse);
      },
    );

    test('older intersection cannot overwrite a newer friend view', () async {
      final stale = Completer<List<dynamic>>();
      final fresh = Completer<List<dynamic>>();
      mockApi.intersectionRequests.addAll([stale, fresh]);
      final notifier = container.read(socialProvider.notifier);
      final newerMovie = Map<String, dynamic>.from(
        mockApi.intersectionResponse.single as Map<String, dynamic>,
      )..['id'] = 202;

      final first = notifier.loadWatchlistIntersection(10);
      final second = notifier.loadWatchlistIntersection(20);
      fresh.complete([newerMovie]);
      await second;
      stale.complete(mockApi.intersectionResponse);
      await first;

      final state = container.read(socialProvider);
      expect(state.intersection.single.id, 202);
      expect(state.loading, isFalse);
    });

    test('rapid profile like toggles are sent and applied in order', () async {
      final firstResponse = Completer<int>();
      final secondResponse = Completer<int>();
      mockApi.profileLikeRequests.addAll([firstResponse, secondResponse]);
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadTopProfiles();

      final initial = container.read(socialProvider).topProfiles.single;
      final first = notifier.toggleProfileLike(initial);
      final liked = container.read(socialProvider).topProfiles.single;
      final second = notifier.toggleProfileLike(liked);

      await Future<void>.delayed(Duration.zero);
      expect(mockApi.profileLikeValues, [true]);
      expect(
        container.read(socialProvider).topProfiles.single.meLiked,
        isFalse,
      );
      firstResponse.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(mockApi.profileLikeValues, [true, false]);
      expect(
        container.read(socialProvider).topProfiles.single.meLiked,
        isFalse,
      );
      secondResponse.complete(0);

      expect(await first, isTrue);
      expect(await second, isTrue);
      final finalProfile = container.read(socialProvider).topProfiles.single;
      expect(finalProfile.meLiked, isFalse);
      expect(finalProfile.likeCount, 0);
    });

    test('stale activity page cannot append after a fresh reload', () async {
      mockApi.paginateActivity = true;
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadActivityFeed();
      final stalePage = Completer<ActivityFeedPage>();
      final freshReload = Completer<ActivityFeedPage>();
      mockApi.activityRequests.addAll([stalePage, freshReload]);

      final loadMore = notifier.loadMoreActivityFeed();
      final reload = notifier.loadActivityFeed();
      final freshItem = Map<String, dynamic>.from(
        mockApi.activityResponse.single as Map<String, dynamic>,
      )..['movie_id'] = 303;
      freshReload.complete(
        ActivityFeedPage(items: [freshItem], hasMore: false),
      );
      await reload;
      final staleItem = Map<String, dynamic>.from(
        mockApi.activityResponse.single as Map<String, dynamic>,
      )..['movie_id'] = 202;
      stalePage.complete(ActivityFeedPage(items: [staleItem], hasMore: false));
      await loadMore;

      final state = container.read(socialProvider);
      expect(state.activityFeed.map((item) => item.movieId), [303]);
      expect(state.activityLoadingMore, isFalse);
    });

    test('stale received page cannot append after a fresh reload', () async {
      mockApi.recommendationsResponse['next_cursor'] = 'page-2';
      mockApi.recommendationsResponse['has_more'] = true;
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadReceivedRecommendations();
      final stalePage = Completer<Map<String, dynamic>>();
      final freshReload = Completer<Map<String, dynamic>>();
      mockApi.receivedPageRequests.add(stalePage);
      mockApi.recommendationsRequests.add(freshReload);

      final loadMore = notifier.loadMoreReceivedRecommendations();
      final reload = notifier.loadReceivedRecommendations();
      freshReload.complete({
        'recommendations': [
          {
            'id': 30,
            'movie_id': 30,
            'is_tv': 0,
            'title': 'Fresh Received',
            'created_at': 30,
            'from_id': 10,
          },
        ],
        'has_more': false,
      });
      await reload;
      stalePage.complete({
        'recommendations': [
          {
            'id': 31,
            'movie_id': 31,
            'is_tv': 0,
            'title': 'Stale Received',
            'created_at': 31,
            'from_id': 10,
          },
        ],
        'has_more': false,
      });
      await loadMore;

      final state = container.read(socialProvider);
      expect(state.receivedRecommendations.map((item) => item.id), [30]);
      expect(state.receivedRecommendationsLoadingMore, isFalse);
    });

    test('stale sent page cannot append after a fresh reload', () async {
      mockApi.sentRecommendationsResponse['next_cursor'] = 'page-2';
      mockApi.sentRecommendationsResponse['has_more'] = true;
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadSentRecommendations();
      final stalePage = Completer<Map<String, dynamic>>();
      final freshReload = Completer<Map<String, dynamic>>();
      mockApi.sentPageRequests.add(stalePage);
      mockApi.sentRecommendationRequests.add(freshReload);

      final loadMore = notifier.loadMoreSentRecommendations();
      final reload = notifier.loadSentRecommendations();
      freshReload.complete({
        'sent': [
          {
            'id': 40,
            'movie_id': 40,
            'is_tv': 0,
            'title': 'Fresh Sent',
            'created_at': 40,
            'to_id': 10,
          },
        ],
        'has_more': false,
      });
      await reload;
      stalePage.complete({
        'sent': [
          {
            'id': 41,
            'movie_id': 41,
            'is_tv': 0,
            'title': 'Stale Sent',
            'created_at': 41,
            'to_id': 10,
          },
        ],
        'has_more': false,
      });
      await loadMore;

      final state = container.read(socialProvider);
      expect(state.sentRecommendations.map((item) => item.id), [40]);
      expect(state.sentRecommendationsLoadingMore, isFalse);
    });

    test(
      'in-flight recommendation load cannot resurrect a deleted item',
      () async {
        final notifier = container.read(socialProvider.notifier);
        await notifier.loadRecommendations();
        final staleLoad = Completer<Map<String, dynamic>>();
        mockApi.recommendationsRequests.add(staleLoad);

        final pendingLoad = notifier.loadRecommendations();
        await Future<void>.delayed(Duration.zero);
        expect(await notifier.deleteRecommendation(1), isTrue);
        staleLoad.complete(mockApi.recommendationsResponse);
        await pendingLoad;

        expect(container.read(socialProvider).recommendations, isEmpty);
        expect(container.read(socialProvider).unseenRecommendations, 0);
      },
    );

    test('failed mark-seen restores the unseen badge', () async {
      final notifier = container.read(socialProvider.notifier);
      await notifier.loadRecommendations();
      mockApi.markSeenShouldFail = true;

      await notifier.markRecommendationsSeen();

      expect(mockApi.markSeenCalled, isTrue);
      expect(container.read(socialProvider).unseenRecommendations, 1);
    });
  });
}
