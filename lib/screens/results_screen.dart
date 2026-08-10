import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/providers.dart';
import '../services/prefs/taste_prefs.dart';
import '../services/recommendation_engine.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_sheet.dart';
import 'results/results_active_filter_bar.dart';
import 'results/results_empty_view.dart';
import 'results/results_error_view.dart';
import 'results/results_filter_sheet.dart';
import 'results/results_language.dart';
import 'results/results_movie_grid.dart';
import 'results/results_skeleton_grid.dart';

@visibleForTesting
bool shouldContinueDiscoverPagination({
  required int batchLength,
  required int freshLength,
}) => batchLength > 0 && freshLength > 0;

@visibleForTesting
bool isCurrentDiscoverRequest({
  required int requestGeneration,
  required int currentGeneration,
}) => requestGeneration == currentGeneration;

class ResultsScreen extends ConsumerStatefulWidget {
  final String? genreStr;
  final int? maxRuntime;
  final int? providerId;
  final String? originalLanguage;
  final String? originCountry;
  final double? minRating;
  final String? decade;
  final String sortBy;
  final String? tvStatus;
  final bool includeMovies;
  final bool includeTv;
  final List<int>? jointGenres;
  final bool isTrending;

  /// true ise her sayfa, kullanıcının tür zevk vektörüyle sıralanır
  /// (mood kısayolları buradan gelir: "Korku gecesi" bile kişiselleşir).
  final bool personalRank;

  const ResultsScreen({
    super.key,
    this.genreStr,
    this.maxRuntime,
    this.providerId,
    this.originalLanguage,
    this.originCountry,
    this.minRating,
    this.decade,
    this.sortBy = 'popularity.desc',
    this.tvStatus,
    this.includeMovies = true,
    this.includeTv = true,
    this.jointGenres,
    this.isTrending = false,
    this.personalRank = false,
  });

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  TmdbService get _service => ref.read(tmdbServiceProvider);

  // Pagination state
  final List<Movie> _movies = [];
  final Set<String> _seenIds = {};
  final ScrollController _scrollCtrl = ScrollController();
  int _page = 1;
  bool _loading = true; // ilk yükleme
  bool _loadingMore = false; // sonraki sayfa yükleniyor
  bool _hasMore = true;
  bool _hasError = false;
  int _loadGeneration = 0;

  // Filter state
  late final int _currentYear = DateTime.now().year;
  late RangeValues _yearRange = RangeValues(1970, _currentYear.toDouble());

  /// Effective language filter. Seeded from [widget.originalLanguage]; clear
  /// sets null and must NOT fall back to the widget again.
  String? _filterLanguage;
  String? _filterDecade;
  String? _filterGenreStr;
  int? _filterProviderId;
  double? _filterMinRating;

  @override
  void initState() {
    super.initState();
    _filterLanguage = widget.originalLanguage;
    _filterDecade = widget.decade;
    _filterGenreStr = widget.genreStr;
    _filterProviderId = widget.providerId;
    _filterMinRating = widget.minRating;
    _scrollCtrl.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_loading &&
        !_loadingMore &&
        _hasMore &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<List<Movie>> _fetchDiscover(int page) {
    if (widget.isTrending) {
      return _service.getTrendingPaged(
        isTV: widget.includeTv && !widget.includeMovies,
        page: page,
      );
    }
    final minYear = _yearRange.start.round();
    final maxYear = _yearRange.end.round();
    final isDefaultRange = !resultsIsYearRangeActive(_yearRange, _currentYear);
    // Custom year range overrides decade; cleared decade stays null.
    final decade = isDefaultRange ? _filterDecade : null;
    final startDate = isDefaultRange ? null : '$minYear-01-01';
    final endDate = isDefaultRange ? null : '$maxYear-12-31';

    return _service.discover(
      genreStr: _filterGenreStr,
      maxRuntime: widget.maxRuntime,
      providerId: _filterProviderId,
      originalLanguage: _filterLanguage,
      originCountry: widget.originCountry,
      minRating: _filterMinRating,
      decade: decade,
      startDate: startDate,
      endDate: endDate,
      sortBy: widget.sortBy,
      tvStatus: widget.tvStatus,
      includeMovies: widget.includeMovies,
      includeTv: widget.includeTv,
      page: page,
    );
  }

  /// Filtreleri uygula ya da ilk açılış: listeyi sıfırla, baştan yükle.
  Future<void> _loadFirstPage() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasError = false;
      _movies.clear();
      _seenIds.clear();
      _page = 1;
      _hasMore = true;
    });
    try {
      final batch = await _personalRankBatch(await _fetchDiscover(1));
      if (!mounted ||
          !isCurrentDiscoverRequest(
            requestGeneration: generation,
            currentGeneration: _loadGeneration,
          )) {
        return;
      }
      setState(() {
        _movies.addAll(
          batch.where(
            (m) => _seenIds.add('${m.isTV ? 'tv' : 'movie'}_${m.id}'),
          ),
        );
        if (batch.isEmpty) _hasMore = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted ||
          !isCurrentDiscoverRequest(
            requestGeneration: generation,
            currentGeneration: _loadGeneration,
          )) {
        return;
      }
      setState(() {
        _hasError = true;
        _hasMore = false;
        _loading = false;
      });
    }
  }

  /// personalRank açıksa sayfayı kullanıcının tür zevkine göre sıralar.
  /// Sayfa-içi sıralama olduğu için sonsuz kaydırma davranışı bozulmaz;
  /// kapalıysa (varsayılan) batch olduğu gibi döner.
  Future<List<Movie>> _personalRankBatch(List<Movie> batch) async {
    if (!widget.personalRank || batch.length < 2) return batch;
    try {
      final weights = await PrefsTastePrefs.getGenreWeights();
      if (weights.isEmpty) return batch;
      final scored = [
        for (final m in batch)
          ScoredMovie(
            m,
            RecommendationEngine.blend(
              genreSim: PrefsTastePrefs.calculateSimilarity(
                weights,
                m.genreIds,
              ),
              voteAverage: m.voteAverage,
            ),
          ),
      ]..sort((a, b) => b.score.compareTo(a.score));
      return scored.map((s) => s.movie).toList();
    } catch (e, st) {
      debugPrint("Personal ranking failed, falling back to API order: $e\n$st");
      return batch;
    }
  }

  Future<void> _loadMore() async {
    final generation = _loadGeneration;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final batch = await _personalRankBatch(await _fetchDiscover(nextPage));
      if (!mounted ||
          !isCurrentDiscoverRequest(
            requestGeneration: generation,
            currentGeneration: _loadGeneration,
          )) {
        return;
      }
      final fresh = batch
          .where((m) => _seenIds.add('${m.isTV ? 'tv' : 'movie'}_${m.id}'))
          .toList();
      setState(() {
        _page = nextPage;
        _movies.addAll(fresh);
        // TMDB boş sayfa döndürdüyse veya yeni öğe kalmadıysa dur.
        _hasMore = shouldContinueDiscoverPagination(
          batchLength: batch.length,
          freshLength: fresh.length,
        );
        _loadingMore = false;
      });
    } catch (e, st) {
      debugPrint("Error loading more results: $e\n$st");
      if (!mounted ||
          !isCurrentDiscoverRequest(
            requestGeneration: generation,
            currentGeneration: _loadGeneration,
          )) {
        return;
      }
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openFilters() async {
    final c = context.c;
    final result = await showModalBottomSheet<ResultsFilterResult>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ResultsFilterSheet(
        initialYearRange: _yearRange,
        initialLanguage: _filterLanguage,
        currentYear: _currentYear,
      ),
    );
    if (result != null) {
      setState(() {
        _yearRange = result.yearRange;
        _filterLanguage = result.language;
        // Applying a custom year range replaces decade intent.
        if (resultsIsYearRangeActive(result.yearRange, _currentYear)) {
          _filterDecade = null;
        }
        if (result.clearRouteFilters) {
          _filterDecade = null;
          _filterGenreStr = null;
          _filterProviderId = null;
          _filterMinRating = null;
        }
      });
      _loadFirstPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.ink, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isTrending
              ? ((widget.includeTv && !widget.includeMovies)
                    ? (AppLocalizations.of(
                            context,
                          )?.get('search_trending_shows') ??
                          'Trend Diziler')
                    : (AppLocalizations.of(
                            context,
                          )?.get('search_trending_movies') ??
                          'Trend Filmler'))
              : (AppLocalizations.of(context)?.get('results_title') ??
                    'Öneriler'),
          style: TextStyle(
            color: c.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: widget.isTrending
            ? null
            : [
                IconButton(
                  icon: Badge(
                    isLabelVisible: _hasActiveFilters,
                    backgroundColor: c.red,
                    child: Icon(Icons.tune_rounded, color: c.ink, size: 20),
                  ),
                  onPressed: _openFilters,
                ),
              ],
      ),
      body: _loading
          ? const ResultsSkeletonGrid()
          : _hasError && _movies.isEmpty
          ? ResultsErrorView(onRetry: _loadFirstPage)
          : _movies.isEmpty
          ? const ResultsEmptyView()
          : _bodyContent(),
    );
  }

  bool get _hasActiveFilters =>
      _filterLanguage != null ||
      resultsIsYearRangeActive(_yearRange, _currentYear) ||
      _filterDecade != null ||
      (_filterGenreStr != null && _filterGenreStr!.isNotEmpty) ||
      _filterProviderId != null ||
      _filterMinRating != null;

  Widget _bodyContent() {
    if (!_hasActiveFilters) return _grid();

    return Column(
      children: [
        ResultsActiveFilterBar(
          filterLanguage: _filterLanguage,
          yearRange: _yearRange,
          currentYear: _currentYear,
          filterDecade: _filterDecade,
          filterGenreStr: _filterGenreStr,
          filterProviderId: _filterProviderId,
          filterMinRating: _filterMinRating,
          onClearLanguage: () {
            setState(() => _filterLanguage = null);
            _loadFirstPage();
          },
          onClearYear: () {
            setState(() {
              _yearRange = RangeValues(1970, _currentYear.toDouble());
              // Clearing year must not revive the mood decade.
              _filterDecade = null;
            });
            _loadFirstPage();
          },
          onClearDecade: () {
            setState(() => _filterDecade = null);
            _loadFirstPage();
          },
          onClearGenre: () {
            setState(() => _filterGenreStr = null);
            _loadFirstPage();
          },
          onClearProvider: () {
            setState(() => _filterProviderId = null);
            _loadFirstPage();
          },
          onClearMinRating: () {
            setState(() => _filterMinRating = null);
            _loadFirstPage();
          },
        ),
        Expanded(child: _grid()),
      ],
    );
  }

  Widget _grid() {
    return ResultsMovieGrid(
      scrollController: _scrollCtrl,
      movies: _movies,
      loadingMore: _loadingMore,
      onTap: _showDetail,
      jointGenres: widget.jointGenres,
    );
  }

  void _showDetail(Movie movie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: _service),
    );
  }
}
