import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ne_izlesem/providers/couch_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';

Map<String, dynamic> sessionJson({
  int id = 7,
  String status = 'active',
  bool isHost = true,
  Map<String, dynamic> myVotes = const {},
  int theirProgress = 0,
  Map<String, dynamic>? matched,
}) => {
  'id': id,
  'status': status,
  'is_host': isHost,
  'friend': {'id': 2, 'display_name': 'Ayşe', 'username': 'ayse'},
  'deck': [
    for (var i = 1; i <= 3; i++)
      {
        'movie_id': 100 + i,
        'is_tv': 0,
        'title': 'Deck $i',
        'poster_path': '/d$i.jpg',
        'vote_average': 7.0,
      },
  ],
  'my_votes': myVotes,
  'their_progress': theirProgress,
  'matched': matched,
  'created_at': 1000,
};

class MockCouchApi implements ApiService {
  Map<String, dynamic>? activeResponse;
  Map<String, dynamic>? voteResponse;
  int voteCalls = 0;
  int? lastVotedMovieId;
  bool? lastVotedLiked;
  bool cancelCalled = false;
  ApiException? voteThrows;
  Map<String, dynamic>? getResponse;

  @override
  Future<Map<String, dynamic>?> getActiveCouchSession() async => activeResponse;

  @override
  Future<Map<String, dynamic>> getCouchSession(int sessionId) async =>
      getResponse ?? sessionJson();

  @override
  Future<Map<String, dynamic>> voteCouchSession({
    required int sessionId,
    required int movieId,
    required bool isTv,
    required bool liked,
  }) async {
    voteCalls++;
    lastVotedMovieId = movieId;
    lastVotedLiked = liked;
    if (voteThrows != null) throw voteThrows!;
    return voteResponse ?? sessionJson();
  }

  @override
  Future<void> cancelCouchSession(int sessionId) async {
    cancelCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockCouchApi mockApi;
  late ProviderContainer container;

  setUp(() {
    mockApi = MockCouchApi();
    container = ProviderContainer(
      overrides: [
        couchProvider.overrideWith((ref) => CouchNotifier(mockApi, ref)),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('CouchSession model', () {
    test('fromJson parses deck, votes, matched and friend name', () {
      final s = CouchSession.fromJson(
        sessionJson(
          status: 'matched',
          myVotes: {'movie_101': true, 'movie_102': false},
          matched: {
            'movie_id': 101,
            'is_tv': 0,
            'title': 'Deck 1',
            'poster_path': '/d1.jpg',
            'vote_average': 7.0,
          },
        ),
      );
      expect(s.friendName, 'Ayşe');
      expect(s.deck, hasLength(3));
      expect(s.myVotes, {'movie_101': true, 'movie_102': false});
      expect(s.matched!.id, 101);
      expect(s.isOpen, isFalse);
    });

    test('nextCard follows deck order and skips voted cards', () {
      final s = CouchSession.fromJson(
        sessionJson(myVotes: {'movie_101': true}),
      );
      expect(s.nextCard!.id, 102);
      expect(s.myProgress, 1);

      final done = CouchSession.fromJson(
        sessionJson(
          myVotes: {'movie_101': true, 'movie_102': false, 'movie_103': false},
        ),
      );
      expect(done.nextCard, isNull);
    });

    test(
      'fromJson tolerates PHP-style empty lists where maps are expected',
      () {
        // PHP boş assoc dizileri `[]` olarak encode eder; güncellenmemiş sunucu
        // my_votes/matched/friend alanlarını liste dönebilir — kırılmamalı.
        final raw = sessionJson();
        raw['my_votes'] = <dynamic>[];
        raw['matched'] = <dynamic>[];
        final s = CouchSession.fromJson(raw);
        expect(s.myVotes, isEmpty);
        expect(s.matched, isNull);
        expect(s.nextCard!.id, 101);
      },
    );

    test('hasPendingInvite only for guest of a pending session', () {
      CouchState stateFor({required String status, required bool isHost}) =>
          CouchState(
            session: CouchSession.fromJson(
              sessionJson(status: status, isHost: isHost),
            ),
          );
      expect(
        stateFor(status: 'pending', isHost: false).hasPendingInvite,
        isTrue,
      );
      expect(
        stateFor(status: 'pending', isHost: true).hasPendingInvite,
        isFalse,
      );
      expect(
        stateFor(status: 'active', isHost: false).hasPendingInvite,
        isFalse,
      );
    });
  });

  group('CouchNotifier', () {
    test('vote sends next unvoted card and applies server state', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(myVotes: {'movie_101': true}));

      mockApi.voteResponse = sessionJson(
        myVotes: {'movie_101': true, 'movie_102': true},
        theirProgress: 2,
      );
      await notifier.vote(true);

      expect(mockApi.lastVotedMovieId, 102);
      expect(mockApi.lastVotedLiked, isTrue);
      final state = container.read(couchProvider);
      expect(state.session!.myProgress, 2);
      expect(state.session!.theirProgress, 2);
    });

    test('vote result can flip session to matched', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson());

      mockApi.voteResponse = sessionJson(
        status: 'matched',
        myVotes: {'movie_101': true},
        matched: {
          'movie_id': 101,
          'is_tv': 0,
          'title': 'Deck 1',
          'poster_path': '/d1.jpg',
          'vote_average': 7.0,
        },
      );
      await notifier.vote(true);

      final s = container.read(couchProvider).session!;
      expect(s.status, 'matched');
      expect(s.matched!.title, 'Deck 1');
    });

    test(
      'vote on closed session refreshes instead of erroring (409)',
      () async {
        final notifier = container.read(couchProvider.notifier);
        notifier.debugSetSession(sessionJson());

        mockApi.voteThrows = ApiException(
          statusCode: 409,
          message: 'Oturum sona erdi.',
        );
        mockApi.getResponse = sessionJson(status: 'cancelled');
        await notifier.vote(true);

        expect(container.read(couchProvider).session!.status, 'cancelled');
        expect(container.read(couchProvider).error, 'couch_session_closed');
      },
    );

    test('refresh to cancelled sets couch_session_closed error', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(status: 'active'));

      mockApi.getResponse = sessionJson(status: 'cancelled');
      await notifier.refresh();

      expect(container.read(couchProvider).session!.status, 'cancelled');
      expect(container.read(couchProvider).error, 'couch_session_closed');
    });

    test('leave does not set session closed error', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(status: 'active'));

      await notifier.leave();

      expect(container.read(couchProvider).session, isNull);
      expect(container.read(couchProvider).error, isNull);
    });

    test('vote ignores duplicate taps while request is in flight', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson());

      mockApi.voteResponse = sessionJson(myVotes: {'movie_101': true});
      await Future.wait([notifier.vote(true), notifier.vote(true)]);

      expect(mockApi.voteCalls, 1);
    });

    test('leave cancels server session and clears local state', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson());

      await notifier.leave();

      expect(mockApi.cancelCalled, isTrue);
      expect(container.read(couchProvider).session, isNull);
    });

    test('no vote is sent when deck is exhausted', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(
        sessionJson(
          myVotes: {'movie_101': true, 'movie_102': false, 'movie_103': false},
        ),
      );
      await notifier.vote(true);
      expect(mockApi.voteCalls, 0);
    });
  });
}
