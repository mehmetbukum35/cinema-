import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../models/social.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import 'auth_provider.dart';

/// "Birlikte Seç" oturumunun istemci görünümü. Sunucu payload'ından türetilir;
/// karşı tarafın oy içeriği sunucudan hiç gelmez (yalnızca ilerleme sayısı).
class CouchSession {
  final int id;
  final String status; // pending | active | matched | ended | cancelled
  final bool isHost;
  final int friendId;
  final String friendName;
  final List<Movie> deck;
  final Map<String, bool> myVotes;
  final int theirProgress;
  final Movie? matched;

  const CouchSession({
    required this.id,
    required this.status,
    required this.isHost,
    required this.friendId,
    required this.friendName,
    required this.deck,
    required this.myVotes,
    required this.theirProgress,
    this.matched,
  });

  factory CouchSession.fromJson(Map<String, dynamic> json) {
    Movie deckMovie(Map<String, dynamic> d) => Movie(
      id: (d['movie_id'] as num?)?.toInt() ?? 0,
      title: d['title'] as String? ?? '',
      posterPath: d['poster_path'] as String?,
      overview: '',
      voteAverage: ((d['vote_average'] as num?) ?? 0).toDouble(),
      isTV: d['is_tv'] == 1 || d['is_tv'] == true || d['is_tv'] == '1',
    );

    final friend = json['friend'] as Map<String, dynamic>? ?? const {};
    final friendName =
        (friend['display_name'] as String?)?.trim().isNotEmpty == true
        ? friend['display_name'] as String
        : '@${friend['username'] ?? '?'}';

    final rawMatched = json['matched'] as Map<String, dynamic>?;
    return CouchSession(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'cancelled',
      isHost: json['is_host'] == true,
      friendId: (friend['id'] as num?)?.toInt() ?? 0,
      friendName: friendName,
      deck: [
        for (final d in (json['deck'] as List<dynamic>? ?? const []))
          deckMovie(d as Map<String, dynamic>),
      ],
      myVotes: {
        for (final e
            in (json['my_votes'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: e.value == true,
      },
      theirProgress: (json['their_progress'] as num?)?.toInt() ?? 0,
      matched: rawMatched != null ? deckMovie(rawMatched) : null,
    );
  }

  bool get isOpen => status == 'pending' || status == 'active';

  /// Sıradaki oylanmamış kart (deste sırasıyla); bittiyse null.
  Movie? get nextCard {
    for (final m in deck) {
      final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
      if (!myVotes.containsKey(key)) return m;
    }
    return null;
  }

  int get myProgress => myVotes.length;
}

class CouchState {
  final CouchSession? session;
  final bool loading;
  final String? error;

  const CouchState({this.session, this.loading = false, this.error});

  CouchState copyWith({
    CouchSession? Function()? session,
    bool? loading,
    String? Function()? error,
  }) {
    return CouchState(
      session: session != null ? session() : this.session,
      loading: loading ?? this.loading,
      error: error != null ? error() : this.error,
    );
  }

  /// Together sekmesindeki rozet: bana gelmiş, henüz katılmadığım davet.
  bool get hasPendingInvite =>
      session != null && session!.status == 'pending' && !session!.isHost;
}

class CouchNotifier extends StateNotifier<CouchState> {
  final ApiService _api;
  final Ref _ref;
  Timer? _pollTimer;

  CouchNotifier(this._api, this._ref) : super(const CouchState());

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Test kancası: oturumu sunucu payload'ıyla doğrudan kurar (auth/engine
  /// bağımlılıklarına girmeden durum geçişleri test edilebilsin).
  @visibleForTesting
  void debugSetSession(Map<String, dynamic>? json) => _apply(json);

  void _apply(Map<String, dynamic>? json) {
    if (!mounted) return;
    final session = json == null ? null : CouchSession.fromJson(json);
    state = state.copyWith(
      session: () => session,
      loading: false,
      error: () => null,
    );
    _syncPolling();
  }

  /// Katılımcısı olduğum canlı oturumu sorgular (Together açılışı + resume).
  Future<void> checkActive() async {
    if (!_ref.read(authProvider).isAuthenticated) return;
    try {
      _apply(await _api.getActiveCouchSession());
    } catch (e) {
      debugPrint('Couch checkActive failed: $e');
    }
  }

  /// Oturum kurar: deste = ortak izleme listesi (önce) + öneri motorunun
  /// kişisel adayları. Motor host'un zevkini bilir; ortak liste zaten iki
  /// tarafın kesişimi olduğundan misafirin zevki de desteye taşınmış olur.
  Future<bool> start(Friend friend, {int deckSize = 20}) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final deckMovies = <Movie>[];
      final seen = <String>{};

      void addAll(Iterable<Movie> movies) {
        for (final m in movies) {
          if (deckMovies.length >= deckSize) return;
          if (m.posterPath == null || m.posterPath!.isEmpty) continue;
          final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
          if (seen.add(key)) deckMovies.add(m);
        }
      }

      // 1) Ortak izleme listesi: ikisinin de zaten izlemek istedikleri —
      // en güçlü adaylar, desteyi bunlar açar.
      try {
        final inter = await _api.getWatchlistIntersection(friend.id);
        addAll(
          inter.map((e) => Movie.fromJson(e as Map<String, dynamic>)).take(8),
        );
      } catch (e) {
        debugPrint('Couch deck intersection failed (skipped): $e');
      }

      // 2) Öneri motoru: host'un puanladıkları hariç kişisel sıralama.
      if (deckMovies.length < deckSize) {
        final engine = _ref.read(recommendationEngineProvider);
        final service = _ref.read(tmdbServiceProvider);
        final candidates = <Movie>[
          ...await engine.fetchSeedCandidates(),
          ...await service.getTrending(),
          ...await service.getPopular(),
        ];
        final excluded = {
          ...await PrefsService.getRatedIds(),
          ...await PrefsService.getBlockedKeys(),
        };
        final ranked = await engine.rankForYou(
          candidates,
          excludedKeys: excluded,
        );
        addAll(ranked);
      }

      final session = await _api.createCouchSession(
        friendId: friend.id,
        deck: [
          for (final m in deckMovies)
            {
              'movie_id': m.id,
              'is_tv': m.isTV ? 1 : 0,
              'title': m.title,
              'poster_path': m.posterPath,
              'vote_average': m.voteAverage,
            },
        ],
      );
      _apply(session);
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        state = state.copyWith(loading: false, error: () => e.message);
      }
      return false;
    } catch (e) {
      debugPrint('Couch start failed: $e');
      if (mounted) {
        state = state.copyWith(loading: false, error: () => e.toString());
      }
      return false;
    }
  }

  /// Sıradaki karta oy verir. Sunucu yanıtı eşleşmeyi anında yansıtır.
  Future<void> vote(bool liked) async {
    final session = state.session;
    final card = session?.nextCard;
    if (session == null || card == null || !session.isOpen) return;
    try {
      final updated = await _api.voteCouchSession(
        sessionId: session.id,
        movieId: card.id,
        isTv: card.isTV,
        liked: liked,
      );
      _apply(updated);
    } on ApiException catch (e) {
      // 409: oturum bu arada bitti/iptal edildi → durumu tazele.
      if (e.statusCode == 409) {
        await refresh();
      } else if (mounted) {
        state = state.copyWith(error: () => e.message);
      }
    } catch (e) {
      debugPrint('Couch vote failed: $e');
    }
  }

  Future<void> refresh() async {
    final session = state.session;
    if (session == null) return;
    try {
      _apply(await _api.getCouchSession(session.id));
    } catch (e) {
      debugPrint('Couch refresh failed: $e');
    }
  }

  /// Açık oturumda iptal; eşleşmiş oturumda kapanış. Yerel durum temizlenir.
  Future<void> leave() async {
    final session = state.session;
    if (session != null) {
      try {
        await _api.cancelCouchSession(session.id);
      } catch (e) {
        debugPrint('Couch cancel failed (ignored): $e');
      }
    }
    _apply(null);
  }

  /// Oturum ekranı açıkken karşı tarafın ilerlemesi/eşleşme için kısa poll.
  /// Ekran kapanınca [stopPolling] çağrılır; matched/ended'da kendiliğinden durur.
  void startPolling() {
    _polling = true;
    _syncPolling();
  }

  void stopPolling() {
    _polling = false;
    _syncPolling();
  }

  bool _polling = false;

  void _syncPolling() {
    final shouldPoll = _polling && (state.session?.isOpen ?? false);
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 2500),
        (_) => refresh(),
      );
    } else if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }
}

final couchProvider = StateNotifierProvider<CouchNotifier, CouchState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return CouchNotifier(api, ref);
});
