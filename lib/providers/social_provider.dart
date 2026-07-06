import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class SocialState {
  final List<dynamic> friends;
  final List<dynamic> pendingReceived;
  final List<dynamic> pendingSent;
  final List<dynamic> activityFeed;
  final List<Movie> intersection;
  final Map<String, dynamic> signals;

  /// Arkadaş id → zevk uyumu skoru (0-100). Veri yetersizse anahtar yoktur.
  final Map<int, int> tasteScores;

  /// Gelen film/dizi önerileri (en yeni önce) ve görülmemiş sayısı.
  final List<dynamic> recommendations;
  final int unseenRecommendations;

  /// Arkadaş id -> O arkadaşın aktivite akışı listesi.
  final Map<int, List<dynamic>> friendActivities;

  final bool loading;
  final String? error;

  SocialState({
    this.friends = const [],
    this.pendingReceived = const [],
    this.pendingSent = const [],
    this.activityFeed = const [],
    this.intersection = const [],
    this.signals = const {},
    this.tasteScores = const {},
    this.recommendations = const [],
    this.unseenRecommendations = 0,
    this.friendActivities = const {},
    this.loading = false,
    this.error,
  });

  SocialState copyWith({
    List<dynamic>? friends,
    List<dynamic>? pendingReceived,
    List<dynamic>? pendingSent,
    List<dynamic>? activityFeed,
    List<Movie>? intersection,
    Map<String, dynamic>? signals,
    Map<int, int>? tasteScores,
    List<dynamic>? recommendations,
    int? unseenRecommendations,
    Map<int, List<dynamic>>? friendActivities,
    bool? loading,
    String? Function()? error,
  }) {
    return SocialState(
      friends: friends ?? this.friends,
      pendingReceived: pendingReceived ?? this.pendingReceived,
      pendingSent: pendingSent ?? this.pendingSent,
      activityFeed: activityFeed ?? this.activityFeed,
      intersection: intersection ?? this.intersection,
      signals: signals ?? this.signals,
      tasteScores: tasteScores ?? this.tasteScores,
      recommendations: recommendations ?? this.recommendations,
      unseenRecommendations:
          unseenRecommendations ?? this.unseenRecommendations,
      friendActivities: friendActivities ?? this.friendActivities,
      loading: loading ?? this.loading,
      error: error != null ? error() : this.error,
    );
  }
}

class SocialNotifier extends StateNotifier<SocialState> {
  final ApiService _apiService;
  final Ref _ref;

  SocialNotifier(this._apiService, this._ref) : super(SocialState());

  Future<void> loadFriendSignals() async {
    try {
      final map = await _apiService.getFriendSignals();
      state = state.copyWith(signals: map);
    } catch (e, st) {
      // Fail silently to keep the swiping UI stable
      debugPrint("Failed to load friend signals: $e\n$st");
    }
  }

  Future<void> loadFriends() async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final res = await _apiService.getFriends();
      state = state.copyWith(
        friends: res['friends'] as List<dynamic>,
        pendingReceived: res['pending_received'] as List<dynamic>,
        pendingSent: res['pending_sent'] as List<dynamic>,
        loading: false,
      );
      // Rozetler için uyum skorlarını arka planda yükle (await edilmez).
      unawaited(loadTasteScores());
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
    }
  }

  Future<void> loadActivityFeed() async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final feed = await _apiService.getActivityFeed();
      state = state.copyWith(activityFeed: feed, loading: false);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
    }
  }

  Future<void> loadFriendActivity(int friendId) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final feed = await _apiService.getActivityFeed(friendId: friendId);
      final map = Map<int, List<dynamic>>.from(state.friendActivities);
      map[friendId] = feed;
      state = state.copyWith(friendActivities: map, loading: false);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
    }
  }

  Future<bool> setupProfile(String username, bool isPublic) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final res = await _apiService.setupProfile(username, isPublic);
      await _ref
          .read(authProvider.notifier)
          .updateUserProfile(
            res['username'] as String,
            (res['is_public'] as int) == 1,
          );
      state = state.copyWith(loading: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
      return false;
    }
  }

  Future<bool> sendFriendRequest(String searchQuery) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      await _apiService.sendFriendRequest(searchQuery);
      state = state.copyWith(loading: false);
      await loadFriends();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
      return false;
    }
  }

  Future<bool> acceptRequest(int friendId) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      await _apiService.acceptFriendRequest(friendId);
      state = state.copyWith(loading: false);
      await loadFriends();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
      return false;
    }
  }

  Future<bool> rejectRequest(int friendId) async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      await _apiService.rejectFriendRequest(friendId);
      state = state.copyWith(loading: false);
      await loadFriends();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
      return false;
    }
  }

  /// Tüm arkadaşlar için zevk uyumu skorlarını çeker.
  /// Sessizce çalışır: hata tek bir arkadaşın rozetini eksik bırakır, UI bozulmaz.
  Future<void> loadTasteScores() async {
    final scores = Map<int, int>.from(state.tasteScores);
    for (final f in state.friends) {
      final id = int.tryParse((f as Map)['id'].toString()) ?? 0;
      if (id == 0) continue;
      try {
        final res = await _apiService.getTasteMatch(id);
        if (res['has_data'] == true) {
          scores[id] = (res['score'] as num).toInt();
        }
      } catch (e, st) {
        // Skorsuz devam et.
        debugPrint("Failed to load taste match for friend $id: $e\n$st");
      }
    }
    if (mounted) state = state.copyWith(tasteScores: scores);
  }

  /// Gelen önerileri yükler.
  Future<void> loadRecommendations() async {
    try {
      final res = await _apiService.getRecommendations();
      state = state.copyWith(
        recommendations: res['recommendations'] as List<dynamic>,
        unseenRecommendations: (res['unseen'] as num?)?.toInt() ?? 0,
      );
    } catch (e, st) {
      // Sessiz: öneri kutusu boş görünür, akış bozulmaz.
      debugPrint("Failed to load recommendations: $e\n$st");
    }
  }

  /// Önerileri görüldü olarak işaretler (rozet sayacını sıfırlar).
  Future<void> markRecommendationsSeen() async {
    if (state.unseenRecommendations == 0) return;
    state = state.copyWith(unseenRecommendations: 0);
    try {
      await _apiService.markRecommendationsSeen();
    } catch (e, st) {
      // Sunucuya yazılamadıysa bir sonraki yüklemede tekrar görünür.
      debugPrint("Failed to mark recommendations seen: $e\n$st");
    }
  }

  /// Arkadaşa film/dizi önerir.
  Future<bool> recommendToFriend({
    required int friendId,
    required Movie movie,
    String? note,
  }) async {
    state = state.copyWith(error: () => null);
    try {
      await _apiService.recommendToFriend(
        friendId: friendId,
        movieId: movie.id,
        isTv: movie.isTV,
        title: movie.title,
        posterPath: movie.posterPath,
        note: note,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
      return false;
    }
  }

  Future<void> loadWatchlistIntersection(int friendId) async {
    state = state.copyWith(loading: true, error: () => null, intersection: []);
    try {
      final list = await _apiService.getWatchlistIntersection(friendId);
      final movies = list
          .map((e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(intersection: movies, loading: false);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: () => e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: () => e.toString());
    }
  }
}

final socialProvider = StateNotifierProvider<SocialNotifier, SocialState>((
  ref,
) {
  final apiService = ref.watch(apiServiceProvider);
  return SocialNotifier(apiService, ref);
});
