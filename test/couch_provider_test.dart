import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ne_izlesem/providers/couch_provider.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/models/social.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:flutter_riverpod/legacy.dart';

class MockAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  MockAuthNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  List<String> usedCouchMoviesResponse = [];
  Completer<Map<String, dynamic>?>? activeGate;
  Completer<Map<String, dynamic>>? sessionGate;
  Completer<Map<String, dynamic>>? voteGate;
  Completer<void>? cancelGate;
  Completer<List<dynamic>>? intersectionGate;
  int createCalls = 0;
  int intersectionCalls = 0;

  @override
  Future<Map<String, dynamic>?> getActiveCouchSession() async =>
      activeGate?.future ?? activeResponse;

  @override
  Future<Map<String, dynamic>> getCouchSession(int sessionId) async =>
      sessionGate?.future ?? getResponse ?? sessionJson();

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
    if (voteGate != null) return voteGate!.future;
    return voteResponse ?? sessionJson();
  }

  @override
  Future<void> cancelCouchSession(int sessionId) async {
    cancelCalled = true;
    if (cancelGate != null) await cancelGate!.future;
  }

  @override
  Future<List<dynamic>> getWatchlistIntersection(int friendId) async {
    intersectionCalls++;
    return intersectionGate?.future ?? const [];
  }

  @override
  Future<Map<String, dynamic>> createCouchSession({
    required int friendId,
    required List<Map<String, dynamic>> deck,
  }) async {
    createCalls++;
    return sessionJson(id: 99);
  }

  @override
  Future<List<String>> getUsedCouchMovies(int friendId) async =>
      usedCouchMoviesResponse;

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
        authProvider.overrideWith(
          (ref) => MockAuthNotifier(
            AuthState(accessToken: 'token', user: {'id': 1}),
          ),
        ),
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

    test('fromJson accepts numeric strings from PDO payloads', () {
      final raw = sessionJson();
      raw['id'] = '7';
      raw['their_progress'] = '2';
      raw['friend'] = {'id': '2', 'display_name': 'Ayşe', 'username': 'ayse'};
      final deck = raw['deck'] as List<dynamic>;
      final firstCard = deck[0] as Map<String, Object>;
      firstCard['movie_id'] = '101';
      firstCard['vote_average'] = '7.5';

      final session = CouchSession.fromJson(raw);
      expect(session.id, 7);
      expect(session.friendId, 2);
      expect(session.theirProgress, 2);
      expect(session.deck.first.id, 101);
      expect(session.deck.first.voteAverage, 7.5);
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

    test('stale active check cannot overwrite a newer session', () async {
      final notifier = container.read(couchProvider.notifier);
      mockApi.activeGate = Completer<Map<String, dynamic>?>();
      final pending = notifier.checkActive();
      await Future<void>.delayed(Duration.zero);
      notifier.debugSetSession(sessionJson(id: 20));

      mockApi.activeGate!.complete(sessionJson(id: 10));
      await pending;

      expect(container.read(couchProvider).session!.id, 20);
    });

    test('stale refresh cannot overwrite a switched session', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(id: 10));
      mockApi.sessionGate = Completer<Map<String, dynamic>>();
      final pending = notifier.refresh();
      notifier.debugSetSession(sessionJson(id: 20));

      mockApi.sessionGate!.complete(sessionJson(id: 10, status: 'matched'));
      await pending;

      expect(container.read(couchProvider).session!.id, 20);
    });

    test('late vote response cannot reopen a left session', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(id: 10));
      mockApi.voteGate = Completer<Map<String, dynamic>>();
      final vote = notifier.vote(true);
      await Future<void>.delayed(Duration.zero);

      await notifier.leave();
      mockApi.voteGate!.complete(
        sessionJson(id: 10, myVotes: {'movie_101': true}),
      );
      await vote;

      expect(container.read(couchProvider).session, isNull);
    });

    test('delayed leave cannot clear a newly discovered session', () async {
      final notifier = container.read(couchProvider.notifier);
      notifier.debugSetSession(sessionJson(id: 10));
      mockApi.cancelGate = Completer<void>();
      final leave = notifier.leave();
      notifier.debugSetSession(sessionJson(id: 20));

      mockApi.cancelGate!.complete();
      await leave;

      expect(container.read(couchProvider).session!.id, 20);
    });

    test('duplicate start taps create only one couch session', () async {
      final notifier = container.read(couchProvider.notifier);
      mockApi.intersectionGate = Completer<List<dynamic>>();
      final friend = Friend(id: 2, username: 'friend');
      final first = notifier.start(friend, deckSize: 1);
      final second = notifier.start(friend, deckSize: 1);

      expect(await second, isFalse);
      expect(mockApi.intersectionCalls, 1);
      mockApi.intersectionGate!.complete([
        {
          'id': 501,
          'title': 'Shared',
          'poster_path': '/shared.jpg',
          'overview': '',
          'vote_average': 7.0,
          'is_tv': 0,
        },
      ]);
      expect(await first, isTrue);
      expect(mockApi.createCalls, 1);
    });
  });
}
