import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs/library_facade.dart';
import '../services/prefs/taste_prefs.dart';
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

class SwipeNotifier extends Notifier<SwipeState> {
  final TmdbService? _serviceOverride;
  final RecommendationEngine? _engineOverride;

  /// false → puanlama sonrası istatistik yenileme, arkadaş sinyali okuma ve
  /// debounce'lu sync tetiklenmez. Testler bunu kapatarak notifier'ı yan
  /// etkisiz sürer (migrasyon öncesi `ref` null bırakılarak yapılıyordu).
  final bool enableSideEffects;

  // `late final` DEGIL: Riverpod 3'te invalidate/rebuild ayni notifier ornegi
  // uzerinde build()'i yeniden kosar, ikinci atama LateInitializationError verir.
  late TmdbService _service;
  late RecommendationEngine _engine;
  Timer? _syncTimer;
  int _loadGeneration = 0;

  SwipeNotifier({
    TmdbService? service,
    RecommendationEngine? engine,
    this.enableSideEffects = true,
  }) : _serviceOverride = service,
       _engineOverride = engine;

  @override
  SwipeState build() {
    _service = _serviceOverride ?? ref.watch(tmdbServiceProvider);
    _engine = _engineOverride ?? ref.watch(recommendationEngineProvider);
    ref.onDispose(_flushPendingSync);
    // build() dönmeden state'e dokunulmamalı; init ilk mikro görevde başlar.
    Future.microtask(init);
    return SwipeState(
      queue: [],
      ratedIds: {},
      page: 1,
      current: 0,
      loading: true,
      loadingMore: false,
      languageFilter: null,
      providerFilter: null,
    );
  }

  /// Puanlamadan sonra: istatistikleri tazele ve push'u 5 sn geciktir — her
  /// swipe'ta ağa çıkmamak için debounce.
  void _afterRate() {
    if (!enableSideEffects) return;
    ref.read(statsProvider.notifier).load(skipSync: true);
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 5), () {
      ref.read(syncProvider.notifier).performSync().catchError((e) {
        debugPrint("Background sync failed on swipe: $e");
      });
    });
  }

  /// Ekran kapanırken bekleyen debounce'u kaybetmeden push'u boşalt.
  void _flushPendingSync() {
    if (_syncTimer?.isActive != true) return;
    _syncTimer?.cancel();
    _syncTimer = null;
    try {
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncProvider.notifier).performSync().catchError((e) {
          debugPrint("Background sync failed on swipe dispose flush: $e");
        });
      }
    } catch (e) {
      debugPrint("Failed to flush swipe sync on dispose: $e");
    }
  }

  Future<void> init() async {
    final generation = _loadGeneration;
    try {
      final rated = await PrefsLibraryFacade.getRatedIds();
      if (ref.mounted) {
        state = state.copyWith(ratedIds: rated);
        await loadMore();
      }
    } catch (e) {
      if (ref.mounted && generation == _loadGeneration) {
        state = state.copyWith(loading: false, error: () => e.toString());
      }
    }
  }

  Future<void> updateFilters({
    String? languageFilter,
    int? providerFilter,
  }) async {
    if (ref.mounted) {
      ++_loadGeneration;
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
    final generation = ++_loadGeneration;
    final startPage = state.page;
    final startLang = state.languageFilter;
    final startProv = state.providerFilter;
    try {
      if (ref.mounted) {
        state = state.copyWith(loadingMore: true, error: () => null);
      }

      final likedGenres = await PrefsTastePrefs.getLikedGenreIds();
      final genreStr = likedGenres.isNotEmpty ? likedGenres.join('|') : null;

      // Kullanıcının dizi/film zevk oranını hesapla (Movie/TV ratio bias)
      double tvRatio = 0.5;
      bool includeMovies = true;
      bool includeTv = true;
      try {
        // Gizli puanlar reco tür ağırlıklarına sızmaz; swipe film/dizi oranını
        // da aynı kurala bağla — aksi halde özel notlar keşif havuzunu büker.
        final ratings = await DatabaseHelper().getRatingsForWeights();
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
      if (!ref.mounted ||
          generation != _loadGeneration ||
          state.page != startPage ||
          state.languageFilter != startLang ||
          state.providerFilter != startProv) {
        return;
      }

      final allCandidates = [...merged, ...similarCandidates];

      Map<String, List<String>> friendSignals = const {};
      if (enableSideEffects) {
        try {
          friendSignals = ref
              .read(socialProvider)
              .signals
              .toRecommendationMap();
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

      if (ref.mounted &&
          generation == _loadGeneration &&
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
      if (ref.mounted &&
          generation == _loadGeneration &&
          state.page == startPage &&
          state.languageFilter == startLang &&
          state.providerFilter == startProv) {
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
    final ratedIndex = state.current;
    final movie = state.queue[ratedIndex];

    // Add to rated IDs
    final key = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
    final newRatedIds = Set<String>.from(state.ratedIds)..add(key);

    // Save to local storage (SQLite)
    await PrefsLibraryFacade.saveRating(
      movie: movie,
      rating: rating,
      metadataLocale: ref.read(localeProvider).languageCode,
    );
    // Zevk profili değişti → keyword vektörü yeniden hesaplansın.
    await _engine.invalidateCache(isNegativeChange: rating <= 1);

    // İsabet telemetrisi: hangi aday kaynağı gerçekten beğeni üretiyor?
    // (rating>=2 = İyi/Harika → isabet). Best-effort; akışı bloklamaz.
    PrefsTastePrefs.recordRecoOutcome(
      source: movie.recoSource ?? 'discover',
      liked: rating >= 2,
    ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));

    if (ref.mounted) {
      // await sırasında refreshRatedIds current'ı ilerletmiş olabilir;
      // kör +1 kart atlar. Yalnızca hâlâ aynı karttaysak ilerle.
      final nextCurrent = state.current == ratedIndex
          ? ratedIndex + 1
          : state.current;
      state = state.copyWith(ratedIds: newRatedIds, current: nextCurrent);
      _afterRate();
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
    final ratingRecord = await PrefsLibraryFacade.getRating(
      movie.id,
      movie.isTV,
    );
    final prevRating = ratingRecord?['rating'] as int?;

    // Delete the rating from DB
    await PrefsLibraryFacade.deleteRating(movie.id, movie.isTV);
    // Zevk profili değişti → keyword vektörü yeniden hesaplansın.
    await _engine.invalidateCache(
      isNegativeChange: prevRating == null || prevRating <= 1,
    );

    // Revert recommendation telemetry outcome
    if (prevRating != null) {
      PrefsTastePrefs.revertRecoOutcome(
        source: movie.recoSource ?? 'discover',
        liked: prevRating >= 2,
      ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
    }

    // Remove from ratedIds
    final key = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
    final newRatedIds = Set<String>.from(state.ratedIds)..remove(key);

    if (ref.mounted) {
      state = state.copyWith(ratedIds: newRatedIds, current: previousIndex);
      _afterRate();
    }
  }

  /// Reload ratedIds from DB (e.g. after rating from movie detail sheet).
  /// Detaydan puanlanan kart destenin başındaysa ilerlet — aksi halde aynı
  /// başlık swipe'ta kalır.
  Future<void> refreshRatedIds() async {
    try {
      final rated = await PrefsLibraryFacade.getRatedIds();
      if (!ref.mounted) return;
      var current = state.current;
      final queue = state.queue;
      while (current < queue.length) {
        final movie = queue[current];
        final key = '${movie.isTV ? 'tv' : 'movie'}_${movie.id}';
        if (!rated.contains(key)) break;
        current++;
      }
      final advanced = current != state.current;
      state = state.copyWith(ratedIds: rated, current: current);
      if (advanced) _afterRate();
      if (current >= queue.length - 5) {
        await loadMore();
      }
    } catch (e) {
      debugPrint('Failed to refresh swipe ratedIds: $e');
    }
  }
}

final swipeProvider = NotifierProvider.autoDispose<SwipeNotifier, SwipeState>(
  SwipeNotifier.new,
);
