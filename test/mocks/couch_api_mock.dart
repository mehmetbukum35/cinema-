import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';

class MockAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  MockAuthNotifier(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;

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
  ApiException? sessionThrows;
  Map<String, dynamic>? getResponse;
  List<String> usedCouchMoviesResponse = [];
  Completer<Map<String, dynamic>?>? activeGate;
  Completer<Map<String, dynamic>>? sessionGate;
  Completer<Map<String, dynamic>>? voteGate;
  Completer<void>? cancelGate;
  Completer<List<dynamic>>? intersectionGate;
  int createCalls = 0;
  List<Map<String, dynamic>>? lastDeck;
  int intersectionCalls = 0;
  int sessionCalls = 0;
  int activeCalls = 0;

  @override
  Future<Map<String, dynamic>?> getActiveCouchSession() async {
    activeCalls++;
    return activeGate?.future ?? activeResponse;
  }

  @override
  Future<Map<String, dynamic>> getCouchSession(int sessionId) async {
    sessionCalls++;
    if (sessionThrows != null) throw sessionThrows!;
    return sessionGate?.future ?? getResponse ?? sessionJson();
  }

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
    lastDeck = deck;
    return sessionJson(id: 99);
  }

  @override
  Future<List<String>> getUsedCouchMovies(int friendId) async =>
      usedCouchMoviesResponse;

  /// SyncService dili buradan okur; ApiService'in gercek alaninin karsiligi.
  @override
  String Function() localeCode = () => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
