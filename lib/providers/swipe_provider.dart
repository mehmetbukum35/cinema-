
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/recommendation_engine.dart';
import '../services/db_helper.dart';
import 'watchlist_provider.dart';
import 'auth_provider.dart';
import 'social_provider.dart';
import '../services/sync_service.dart';

class SwipeState {
  final List<Movie> queue;
  final Set<String> ratedIds;
  final int page;
  final int current;
  final bool loading;
  final bool loadingMore;
  final String? languageFilter;
  final int? providerFilter;
  final String? error;

  SwipeState({
    required this.queue,
    required this.ratedIds,
    required this.page,
    required this.current,
    required this.loading,
    required this.loadingMore,
    this.languageFilter,
    this.providerFilter,
    this.error,
  });

  SwipeState copyWith({
    List<Movie>? queue,
    Set<String>? ratedIds,
    int? page,
    int? current,
    bool? loading,
    bool? loadingMore,
    String? Function()? languageFilter,
    int? Function()? providerFilter,
    String? Function()? error,
  }) {
    return SwipeState(
      queue: queue ?? this.queue,
      ratedIds: ratedIds ?? this.ratedIds,
      page: page ?? this.page,
      current: current ?? this.current,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      languageFilter: languageFilter != null
          ? languageFilter()
          : this.languageFilter,
      providerFilter: providerFilter != null
          ? providerFilter()
          : this.providerFilter,
      error: error != null ? error() : this.error,
    );
  }
}

class SwipeNotifier extends StateNotifier<SwipeState> {
  final TmdbService _service;
  final RecommendationEngine _engine;
  final Ref? ref;
  final void Function()? onRated;

  SwipeNotifier(this._service, this._engine, {this.ref, this.onRated})
    : super(
        SwipeState(
          queue: [],
          ratedIds: {},
          page: 1,
          current: 0,
          loading: true,
          loadingMore: false,
          languageFilter: null,
          providerFilter: null,
        ),
      ) {
    init();
  }

  Future<void> init() async {
    try {
      final rated = await PrefsService.getRatedIds();
      if (mounted) {
        state = state.copyWith(ratedIds: rated);
        await loadMore();
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(loading: false, error: () => e.toString());
      }
    }
  }

  Future<void> updateFilters({
    String? languageFilter,
    int? providerFilter,
  }) async {
    if (mounted) {
      state = state.copyWith(
        queue: [],
        page: 1,
        current: 0,
        loading: true,
        loadingMore: false,
        languageFilter: () => languageFilter,
        providerFilter: () => providerFilter,
        error: () => null,
      );
      await loadMore();
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore) return;
    final startPage = state.page;
    final startLang = state.languageFilter;
    final startProv = state.providerFilter;
    try {
      if (mounted) {
        state = state.copyWith(loadingMore: true, error: () => null);
      }

      final likedGenres = await PrefsService.getLikedGenreIds();
      final genreStr = likedGenres.isNotEmpty ? likedGenres.join('|') : null;

      // Kullanıcının dizi/film zevk oranını hesapla (Movie/TV ratio bias)
      double tvRatio = 0.5;
      bool includeMovies = true;
      bool includeTv = true;
      try {
        final ratings = await DatabaseHelper().getRatings();
        if (ratings.length >= 5) {
          final tvCount = ratings.where((r) => r['isTV'] == true).length;
          tvRatio = tvCount / ratings.length;
          includeMovies = tvRatio <= 0.75;
          includeTv = tvRatio >= 0.25;
        }
      } catch (e) {
        debugPrint("Failed to calculate tvRatio from history: $e");
      }

      final List<Movie> merged;
      if (startLang != null || startProv != null) {
        merged = await _service.discover(
          genreStr: genreStr,
          originalLanguage: startLang,
          providerId: startProv,
          includeMovies: includeMovies,
          includeTv: includeTv,
          page: startPage,
        );
      } else {
        if (likedGenres.isNotEmpty) {
          final results = await Future.wait([
            _service.discover(
              genreStr: genreStr,
              includeMovies: includeMovies,
              includeTv: includeTv,
              page: startPage,
            ),
            _service.discover(
              genreStr: genreStr,
              includeMovies: includeMovies,
              includeTv: includeTv,
              page: startPage,
              sortBy: 'vote_average.desc',
            ),
          ]);
          final seen = <String>{};
          merged = [...results[0], ...results[1]].where((m) {
            final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
            return seen.add(key);
          }).toList();
        } else {
          final List<Movie> movies;
          final List<Movie> shows;
          if (tvRatio >= 0.75) {
            movies = const [];
            shows = await _service.getPopular(isTV: true, page: startPage);
          } else if (tvRatio <= 0.25) {
            movies = await _service.getPopular(isTV: false, page: startPage);
            shows = const [];
          } else {
            final results = await Future.wait([
              _service.getPopular(isTV: false, page: startPage),
              _service.getPopular(isTV: true, page: startPage),
            ]);
            movies = results[0];
            shows = results[1];
          }
          merged = <Movie>[];
          for (var i = 0; i < movies.length || i < shows.length; i++) {
            if (i < movies.length) merged.add(movies[i]);
            if (i < shows.length) merged.add(shows[i]);
          }
        }
      }

      final similarCandidates = (startLang == null && startProv == null)
          ? await _engine.fetchSeedCandidates()
          : <Movie>[];

      // Check if state changed/reset during network call
      if (!mounted ||
          state.page != startPage ||
          state.languageFilter != startLang ||
          state.providerFilter != startProv) {
        return;
      }

      final allCandidates = [...merged, ...similarCandidates];

      // Load friend signals from socialProvider state
      Map<String, List<String>> friendSignals = const {};
      final refInstance = ref;
      if (refInstance != null) {
        try {
          final rawSignals = refInstance.read(socialProvider).signals;
          friendSignals = rawSignals.map(
            (k, v) => MapEntry(
              k,
              (v as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          );
        } catch (e) {
          debugPrint("Failed to read friend signals from provider: $e");
        }
      }

      final queueKeys = state.queue
          .map((m) => "${m.isTV ? 'tv' : 'movie'}_${m.id}")
          .toSet();

      final excludedKeys = {...state.ratedIds, ...queueKeys};

      final fresh = await _engine.rankForYou(
        allCandidates,
        excludedKeys: excludedKeys,
        friendSignals: friendSignals,
        diversify: true,
        jitter: 0.08,
        suppressFranchises: true,
      );

      if (mounted &&
          state.page == startPage &&
          state.languageFilter == startLang &&
          state.providerFilter == startProv) {
        state = state.copyWith(
          queue: [...state.queue, ...fresh],
          page: state.page + 1,
          loading: false,
          loadingMore: false,
          error: () => null,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          error: () => e.toString(),
        );
      }
    }
  }

  Future<void> rate(int rating) async {
    if (state.current >= state.queue.length) return;
    final movie = state.queue[state.current];

    // Add to rated IDs
    final key = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
    final newRatedIds = Set<String>.from(state.ratedIds)..add(key);

    // Save to local storage (SQLite)
    await PrefsService.saveRating(movie: movie, rating: rating);
    // Zevk profili değişti → keyword vektörü yeniden hesaplansın.
    _engine.invalidateCache(isNegativeChange: rating <= 1);

    // İsabet telemetrisi: hangi aday kaynağı gerçekten beğeni üretiyor?
    // (rating>=2 = İyi/Harika → isabet). Best-effort; akışı bloklamaz.
    PrefsService.recordRecoOutcome(
      source: movie.recoSource ?? 'discover',
      liked: rating >= 2,
    ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));

    if (mounted) {
      state = state.copyWith(ratedIds: newRatedIds, current: state.current + 1);
      onRated?.call();
    }

    // Preload more when near end of the current queue
    if (state.current >= state.queue.length - 5) {
      await loadMore();
    }
  }

  Future<void> undo() async {
    if (state.current == 0) return;
    final previousIndex = state.current - 1;
    final movie = state.queue[previousIndex];

    // Get the rating before deleting to check if it was a dislike
    final ratingRecord = await PrefsService.getRating(movie.id, movie.isTV);
    final prevRating = ratingRecord?['rating'] as int?;

    // Delete the rating from DB
    await PrefsService.deleteRating(movie.id, movie.isTV);
    // Zevk profili değişti → keyword vektörü yeniden hesaplansın.
    _engine.invalidateCache(isNegativeChange: prevRating == null || prevRating <= 1);

    // Remove from ratedIds
    final key = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
    final newRatedIds = Set<String>.from(state.ratedIds)..remove(key);

    if (mounted) {
      state = state.copyWith(ratedIds: newRatedIds, current: previousIndex);
      onRated?.call();
    }
  }
}

final swipeProvider =
    StateNotifierProvider.autoDispose<SwipeNotifier, SwipeState>((ref) {
      final service = ref.watch(tmdbServiceProvider);
      final engine = ref.watch(recommendationEngineProvider);
      return SwipeNotifier(
        service,
        engine,
        ref: ref,
        onRated: () {
          ref.read(statsProvider.notifier).load();
          final auth = ref.read(authProvider);
          if (auth.isAuthenticated) {
            ref.read(syncProvider.notifier).performSync().catchError((e) {
              debugPrint("Background sync failed on swipe: $e");
            });
          }
        },
      );
    });
