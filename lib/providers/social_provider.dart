import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../models/social.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class SocialState {
  final List<Friend> friends;
  final List<Friend> pendingReceived;
  final List<Friend> pendingSent;
  final List<ActivityItem> activityFeed;
  final List<Movie> intersection;
  final FriendSignals signals;

  /// Arkadaş id → zevk uyumu skoru (0-100). Veri yetersizse anahtar yoktur.
  final Map<int, int> tasteScores;

  /// Gelen film/dizi önerileri (en yeni önce) ve görülmemiş sayısı.
  final List<RecommendationInboxItem> recommendations;
  final int unseenRecommendations;

  /// Kullanıcının arkadaşlarına gönderdiği öneriler (en yeni önce).
  final List<SentRecommendationItem> sentRecommendations;

  /// Arkadaş id -> O arkadaşın aktivite akışı listesi.
  final Map<int, List<ActivityItem>> friendActivities;

  /// "Popüler Listeler": en çok beğeni alan üyeler (sunucudan sıralı gelir).
  final List<TopProfile> topProfiles;
  final bool topProfilesLoading;

  final bool loading;
  final String? error;

  SocialState({
    this.friends = const [],
    this.pendingReceived = const [],
    this.pendingSent = const [],
    this.activityFeed = const [],
    this.intersection = const [],
    this.signals = const FriendSignals(),
    this.tasteScores = const {},
    this.recommendations = const [],
    this.unseenRecommendations = 0,
    this.sentRecommendations = const [],
    this.friendActivities = const {},
    this.topProfiles = const [],
    this.topProfilesLoading = false,
    this.loading = false,
    this.error,
  });

  SocialState copyWith({
    List<Friend>? friends,
    List<Friend>? pendingReceived,
    List<Friend>? pendingSent,
    List<ActivityItem>? activityFeed,
    List<Movie>? intersection,
    FriendSignals? signals,
    Map<int, int>? tasteScores,
    List<RecommendationInboxItem>? recommendations,
    int? unseenRecommendations,
    List<SentRecommendationItem>? sentRecommendations,
    Map<int, List<ActivityItem>>? friendActivities,
    List<TopProfile>? topProfiles,
    bool? topProfilesLoading,
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
      sentRecommendations: sentRecommendations ?? this.sentRecommendations,
      friendActivities: friendActivities ?? this.friendActivities,
      topProfiles: topProfiles ?? this.topProfiles,
      topProfilesLoading: topProfilesLoading ?? this.topProfilesLoading,
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

      final friendsList =
          (res['friends'] as List<dynamic>?)
              ?.map((x) => Friend.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const [];
      final pendingReceivedList =
          (res['pending_received'] as List<dynamic>?)
              ?.map((x) => Friend.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const [];
      final pendingSentList =
          (res['pending_sent'] as List<dynamic>?)
              ?.map((x) => Friend.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const [];

      state = state.copyWith(
        friends: friendsList,
        pendingReceived: pendingReceivedList,
        pendingSent: pendingSentList,
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
      final feedList =
          (feed as List<dynamic>?)
              ?.map((x) => ActivityItem.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const [];
      state = state.copyWith(activityFeed: feedList, loading: false);
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
      final feedList =
          (feed as List<dynamic>?)
              ?.map((x) => ActivityItem.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const [];
      final map = Map<int, List<ActivityItem>>.from(state.friendActivities);
      map[friendId] = feedList;
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
      unawaited(loadFriends());
      unawaited(loadActivityFeed());
      unawaited(loadRecommendations());
      unawaited(loadSentRecommendations());
      unawaited(loadTopProfiles());
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
  /// Önce toplu uç denenir (tek HTTP isteği); uç yoksa (eski sunucu, 404)
  /// arkadaş başına tekil isteğe geri düşülür. Sessizce çalışır: hata tek
  /// bir arkadaşın rozetini eksik bırakır, UI bozulmaz.
  Future<void> loadTasteScores() async {
    final scores = Map<int, int>.from(state.tasteScores);
    try {
      final list = await _apiService.getAllTasteMatches();
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['friend_id'] as num?)?.toInt() ?? 0;
        if (id == 0 || item['has_data'] != true) continue;
        scores[id] = ((item['score'] as num?) ?? 0).toInt();
      }
      if (mounted) state = state.copyWith(tasteScores: scores);
      return;
    } on ApiException catch (e) {
      if (e.statusCode != 404) {
        debugPrint("Failed to load taste matches in batch: $e");
        return;
      }
      // 404 → sunucu henüz taste-all ucunu bilmiyor; tekil uca düş.
    } catch (e, st) {
      debugPrint("Failed to load taste matches in batch: $e\n$st");
      return;
    }

    for (final f in state.friends) {
      final id = f.id;
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
      final recList =
          (res['recommendations'] as List<dynamic>?)
              ?.map(
                (x) =>
                    RecommendationInboxItem.fromJson(x as Map<String, dynamic>),
              )
              .toList() ??
          const [];
      state = state.copyWith(
        recommendations: recList,
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

  /// Kullanıcının arkadaşlarına gönderdiği önerileri yükler.
  Future<void> loadSentRecommendations() async {
    try {
      final res = await _apiService.getSentRecommendations();
      final list =
          (res['sent'] as List<dynamic>?)
              ?.map(
                (x) =>
                    SentRecommendationItem.fromJson(x as Map<String, dynamic>),
              )
              .toList() ??
          const [];
      state = state.copyWith(sentRecommendations: list);
    } catch (e, st) {
      debugPrint("Failed to load sent recommendations: $e\n$st");
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
      unawaited(loadSentRecommendations());
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: () => e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: () => e.toString());
      return false;
    }
  }

  /// "Popüler Listeler" sıralamasını yükler.
  Future<void> loadTopProfiles() async {
    state = state.copyWith(topProfilesLoading: true, error: () => null);
    try {
      final res = await _apiService.getTopProfiles();
      final list =
          (res['profiles'] as List<dynamic>?)
              ?.map((x) => TopProfile.fromJson(x as Map<String, dynamic>))
              .toList() ??
          const <TopProfile>[];
      state = state.copyWith(topProfiles: list, topProfilesLoading: false);
    } on ApiException catch (e) {
      state = state.copyWith(topProfilesLoading: false, error: () => e.message);
    } catch (e) {
      state = state.copyWith(
        topProfilesLoading: false,
        error: () => e.toString(),
      );
    }
  }

  /// Profil beğenisini değiştirir. Önce iyimser (optimistic) güncelleme yapılır;
  /// sunucu hata verirse eski duruma geri dönülür ve false döner (çağıran
  /// kullanıcıya bildirir — kalp sessizce eski haline dönünce anlaşılmıyordu).
  /// Sıra numaraları sunucu sıralaması bozulmasın diye yerinde bırakılır.
  Future<bool> toggleProfileLike(TopProfile profile) async {
    final newLiked = !profile.meLiked;
    List<TopProfile> apply(List<TopProfile> list, int likeCount) => [
      for (final p in list)
        if (p.id == profile.id)
          p.copyWith(meLiked: newLiked, likeCount: likeCount)
        else
          p,
    ];

    final optimisticCount = profile.likeCount + (newLiked ? 1 : -1);
    state = state.copyWith(
      topProfiles: apply(state.topProfiles, optimisticCount),
    );

    try {
      final serverCount = await _apiService.likeProfile(profile.id, newLiked);
      state = state.copyWith(
        topProfiles: apply(state.topProfiles, serverCount),
      );
      return true;
    } catch (e, st) {
      debugPrint("Failed to toggle profile like: $e\n$st");
      // Geri al.
      state = state.copyWith(
        topProfiles: apply(state.topProfiles, profile.likeCount),
      );
      state = state.copyWith(
        topProfiles: [
          for (final p in state.topProfiles)
            if (p.id == profile.id) p.copyWith(meLiked: profile.meLiked) else p,
        ],
      );
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
