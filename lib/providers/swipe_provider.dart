import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import 'watchlist_provider.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';
import '../services/db_helper.dart';

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
  final void Function()? onRated;

  /// Kullanıcının anahtar kelime zevk vektörü (keyword_id → ağırlık).
  /// Beğenilen (İyi/Harika) yapımların keyword'lerinden kurulur, memoize edilir;
  /// yeni puan verilince/undo'da null'lanıp yeniden hesaplanır.
  Map<int, double>? _userKeywordVector;

  SwipeNotifier(this._service, {this.onRated})
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

  /// Beğenilen (rating>=2) yapımların keyword'lerinden kullanıcı zevk vektörünü
  /// kurar. Harika(3)→+2, İyi(2)→+1, zaman decay'li (prefs ile aynı yarı ömür).
  /// En yeni 15 beğeni ile sınırlıdır; keyword uçları cache'li olduğundan
  /// tekrar çağrılarda ağ maliyeti ~sıfırdır. Sonuç memoize edilir.
  Future<Map<int, double>> _getUserKeywordVector() async {
    final cached = _userKeywordVector;
    if (cached != null) return cached;

    final vec = <int, double>{};
    try {
      final ratings = await DatabaseHelper().getRatings();
      final liked =
          ratings.where((r) => (r['rating'] as int) >= 2).toList()
            ..sort(
              (a, b) =>
                  (b['created_at'] as int).compareTo(a['created_at'] as int),
            );
      final seeds = liked.take(15).toList();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final kwLists = await Future.wait(
        seeds.map((r) {
          final id = r['id'] as int;
          final isTV = r['isTV'] as bool? ?? false;
          return _service
              .getKeywordIds(id, isTV: isTV)
              .catchError((_) => <int>[]);
        }),
      );

      for (var i = 0; i < seeds.length; i++) {
        final r = seeds[i];
        final rating = r['rating'] as int;
        final base = rating == 3 ? 2.0 : 1.0; // Harika daha güçlü
        final createdAt = r['created_at'] as int;
        final days = (nowMs - createdAt) / 86400000.0;
        final decay = exp(-0.00385 * days);
        final w = base * decay;
        for (final kid in kwLists[i]) {
          vec[kid] = (vec[kid] ?? 0.0) + w;
        }
      }
    } catch (_) {
      // Hata → boş vektör; keyword fazı sessizce atlanır (cold-start gibi).
    }

    _userKeywordVector = vec;
    return vec;
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

      final List<Movie> merged;
      if (startLang != null || startProv != null) {
        merged = await _service.discover(
          genreStr: genreStr,
          originalLanguage: startLang,
          providerId: startProv,
          page: startPage,
        );
      } else {
        if (likedGenres.isNotEmpty) {
          final results = await Future.wait([
            _service.discover(genreStr: genreStr, page: startPage),
            _service.discover(
              genreStr: genreStr,
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
          final results = await Future.wait([
            _service.getPopular(isTV: false, page: startPage),
            _service.getPopular(isTV: true, page: startPage),
          ]);
          final movies = results[0];
          final shows = results[1];
          merged = <Movie>[];
          for (var i = 0; i < movies.length || i < shows.length; i++) {
            if (i < movies.length) merged.add(movies[i]);
            if (i < shows.length) merged.add(shows[i]);
          }
        }
      }

      // Öneri Motoru: Kullanıcının 4 veya 5 yıldız (rating=3) verdiği yapımları tohum (seed) yap
      final db = DatabaseHelper();
      final ratings = await db.getRatings();
      final highRated = ratings
          .where((r) => r['rating'] == 3)
          .toList()
        ..sort((a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int));
      final seeds = highRated.take(3).toList();

      final List<Movie> similarCandidates = [];
      if (seeds.isNotEmpty) {
        try {
          final similarFutures = seeds.map((s) {
            final int id = s['id'] as int;
            final bool isTV = s['isTV'] as bool? ?? false;
            return Future.wait([
              _service.getRecommendations(id, isTV: isTV),
              _service.getSimilar(id, isTV: isTV),
            ]);
          }).toList();

          final similarResults = await Future.wait(similarFutures);
          for (final res in similarResults) {
            similarCandidates.addAll(res[0]); // recommendations
            similarCandidates.addAll(res[1]); // similar
          }
        } catch (_) {}
      }

      // Check if state changed/reset during network call
      if (!mounted ||
          state.page != startPage ||
          state.languageFilter != startLang ||
          state.providerFilter != startProv) {
        return;
      }

      // Filter out already-rated movies AND movies already in queue AND duplicates
      final queueKeys = state.queue
          .map((m) => "${m.isTV ? 'tv' : 'movie'}_${m.id}")
          .toSet();

      final allCandidates = [...merged, ...similarCandidates];
      final seenKeys = <String>{};
      final freshUnsorted = <Movie>[];

      for (final m in allCandidates) {
        final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
        if (!state.ratedIds.contains(key) &&
            !queueKeys.contains(key) &&
            seenKeys.add(key)) {
          freshUnsorted.add(m);
        }
      }

      // Cosine similarity and jittered ranking
      final userWeights = await PrefsService.getGenreWeights();
      final random = Random();
      final List<Map<String, dynamic>> scoredFresh = [];

      for (final m in freshUnsorted) {
        final double similarity = PrefsService.calculateSimilarity(
          userWeights,
          m.genreIds,
        );
        final double rawScore = 0.7 * similarity + 0.3 * (m.voteAverage / 10.0);

        // Sigmoid normalisation centering around 0.2 (cold start average)
        // Map raw score to realistic display match percentage [40, 98]
        final double z = (rawScore - 0.2) * 4.0;
        final double sigmoid = 1.0 / (1.0 + exp(-z));
        final int displayScore = (40 + (sigmoid * 58)).round();
        m.personalizedMatchScore = displayScore.clamp(40, 98);

        // Add jitter (±0.08 noise) to dynamically change queue order each time
        final double jitteredScore =
            rawScore + (random.nextDouble() * 0.16 - 0.08);
        scoredFresh.add({'movie': m, 'score': jitteredScore});
      }

      scoredFresh.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );
      var fresh = scoredFresh.map((e) => e['movie'] as Movie).toList();

      // ─── Keyword re-rank fazı (ucuz recall → hassas precision) ──────────────
      // Tür-tabanlı sıralama zaten yapıldı; şimdi görünecek ilk dilimi
      // (top-K) kullanıcının keyword zevk vektörüyle yeniden puanlayıp
      // sıralıyoruz. Böylece "seni tanıyor" hissi sıralama seviyesine çıkıyor,
      // maliyet ise K adet (cache'li) keyword isteğiyle sınırlı kalıyor.
      final userKwVector = await _getUserKeywordVector();
      if (userKwVector.isNotEmpty && fresh.isNotEmpty) {
        const kRerank = 15;
        final topSlice = fresh.take(kRerank).toList();
        final rest = fresh.skip(kRerank).toList();

        final kwLists = await Future.wait(
          topSlice.map(
            (m) => _service
                .getKeywordIds(m.id, isTV: m.isTV)
                .catchError((_) => <int>[]),
          ),
        );

        // Durum re-rank sırasında değiştiyse bu partiyi atla.
        if (mounted &&
            state.page == startPage &&
            state.languageFilter == startLang &&
            state.providerFilter == startProv) {
          final reranked = <Map<String, dynamic>>[];
          for (var i = 0; i < topSlice.length; i++) {
            final m = topSlice[i];
            final genreSim = PrefsService.calculateSimilarity(
              userWeights,
              m.genreIds,
            );
            final kwSim = PrefsService.calculateSimilarity(
              userKwVector,
              kwLists[i],
            );
            // Harman: tür lider, keyword güçlü ikinci sinyal, TMDB puanı taban.
            final double raw =
                0.45 * genreSim + 0.25 * kwSim + 0.30 * (m.voteAverage / 10.0);

            final double z = (raw - 0.2) * 4.0;
            final double sigmoid = 1.0 / (1.0 + exp(-z));
            m.personalizedMatchScore = (40 + (sigmoid * 58)).round().clamp(
              40,
              98,
            );
            reranked.add({'movie': m, 'score': raw});
          }
          reranked.sort(
            (a, b) => (b['score'] as double).compareTo(a['score'] as double),
          );
          fresh = [
            ...reranked.map((e) => e['movie'] as Movie),
            ...rest,
          ];
        }
      }

      if (mounted) {
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
    _userKeywordVector = null;

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

    // Delete the rating from DB
    await PrefsService.deleteRating(movie.id, movie.isTV);
    // Zevk profili değişti → keyword vektörü yeniden hesaplansın.
    _userKeywordVector = null;

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
      return SwipeNotifier(
        service,
        onRated: () {
          ref.read(statsProvider.notifier).load();
          final auth = ref.read(authProvider);
          if (auth.isAuthenticated) {
            ref.read(syncServiceProvider).sync().catchError((_) {});
          }
        },
      );
    });
