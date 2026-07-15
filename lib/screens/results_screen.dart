import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/providers.dart';
import '../services/prefs_service.dart';
import '../services/recommendation_engine.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_sheet.dart';
import 'results/movie_card.dart';
import 'results/skeleton_card.dart';
import 'results/lang_chip.dart';

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

  // Filter state
  late final int _currentYear = DateTime.now().year;
  late RangeValues _yearRange = RangeValues(1970, _currentYear.toDouble());
  String? _filterLanguage;

  bool _isYearRangeActive(RangeValues range) {
    return range.start.round() != 1970 || range.end.round() != _currentYear;
  }

  static String _getLanguageLabel(String code, String fallback) {
    final isTr = ui.PlatformDispatcher.instance.locale.languageCode == 'tr';
    if (isTr) return fallback;
    switch (code) {
      case 'tr':
        return 'Turkish';
      case 'en':
        return 'English';
      case 'ja':
        return 'Japanese';
      case 'ko':
        return 'Korean';
      case 'fr':
        return 'French';
      case 'es':
        return 'Spanish';
      case 'de':
        return 'German';
      case 'it':
        return 'Italian';
      case 'hi':
        return 'Hindi';
      default:
        return fallback;
    }
  }

  static const _languages = [
    (code: 'tr', label: 'Türkçe'),
    (code: 'en', label: 'İngilizce'),
    (code: 'ja', label: 'Japonca'),
    (code: 'ko', label: 'Korece'),
    (code: 'fr', label: 'Fransızca'),
    (code: 'es', label: 'İspanyolca'),
    (code: 'de', label: 'Almanca'),
    (code: 'it', label: 'İtalyanca'),
    (code: 'hi', label: 'Hintçe'),
  ];

  @override
  void initState() {
    super.initState();
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
    final isDefaultRange = !_isYearRangeActive(_yearRange);
    final decade = isDefaultRange ? widget.decade : null;
    final startDate = isDefaultRange ? null : '$minYear-01-01';
    final endDate = isDefaultRange ? null : '$maxYear-12-31';

    return _service.discover(
      genreStr: widget.genreStr,
      maxRuntime: widget.maxRuntime,
      providerId: widget.providerId,
      originalLanguage: _filterLanguage ?? widget.originalLanguage,
      originCountry: widget.originCountry,
      minRating: widget.minRating,
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
    setState(() {
      _loading = true;
      _hasError = false;
      _movies.clear();
      _seenIds.clear();
      _page = 1;
      _hasMore = true;
    });
    try {
      final batch = await _personalRankBatch(await _fetchDiscover(1));
      if (!mounted) return;
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
      if (!mounted) return;
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
      final weights = await PrefsService.getGenreWeights();
      if (weights.isEmpty) return batch;
      final scored = [
        for (final m in batch)
          ScoredMovie(
            m,
            RecommendationEngine.blend(
              genreSim: PrefsService.calculateSimilarity(weights, m.genreIds),
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
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final batch = await _personalRankBatch(await _fetchDiscover(nextPage));
      if (!mounted) return;
      final fresh = batch
          .where((m) => _seenIds.add('${m.isTV ? 'tv' : 'movie'}_${m.id}'))
          .toList();
      setState(() {
        _page = nextPage;
        _movies.addAll(fresh);
        // TMDB boş sayfa döndürdüyse veya yeni öğe kalmadıysa dur.
        if (batch.isEmpty) _hasMore = false;
        _loadingMore = false;
      });
    } catch (e, st) {
      debugPrint("Error loading more results: $e\n$st");
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openFilters() async {
    final c = context.c;
    RangeValues tempYear = _yearRange;
    String? tempLang = _filterLanguage;

    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) {
                    final suffix =
                        (tempLang != null || _isYearRangeActive(tempYear))
                        ? (AppLocalizations.of(context)?.get('active') ??
                              ' (Active)')
                        : '';
                    return Text(
                      '${AppLocalizations.of(context)?.get('filter') ?? 'Filter'}$suffix',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Year range
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) {
                        return Text(
                          '${AppLocalizations.of(context)?.get('year') ?? 'Year'}: ${tempYear.start.round()} – ${tempYear.end.round()}',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    if (_isYearRangeActive(tempYear)) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              RangeSlider(
                values: tempYear,
                min: 1970,
                max: _currentYear.toDouble(),
                divisions: _currentYear - 1970,
                activeColor: c.red,
                inactiveColor: c.card,
                onChanged: (v) => setModal(() => tempYear = v),
              ),
              const SizedBox(height: 16),
              // Language
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context)?.get('language') ??
                              'LANGUAGE',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    if (tempLang != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Builder(
                    builder: (context) {
                      return ResultsLangChip(
                        label:
                            AppLocalizations.of(context)?.get('lang_all') ??
                            'All',
                        selected: tempLang == null,
                        onTap: () => setModal(() => tempLang = null),
                      );
                    },
                  ),
                  ..._languages.map(
                    (l) => ResultsLangChip(
                      label: _getLanguageLabel(l.code, l.label),
                      selected: tempLang == l.code,
                      onTap: () => setModal(
                        () => tempLang = tempLang == l.code ? null : l.code,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setModal(() {
                          tempYear = RangeValues(1970, _currentYear.toDouble());
                          tempLang = null;
                        });
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.of(context)?.get('search_clear') ??
                              'Sıfırla',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _yearRange = tempYear;
                        _filterLanguage = tempLang;
                        _loadFirstPage();
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.of(context)?.locale.languageCode ==
                                  'tr'
                              ? 'Uygula'
                              : 'Apply',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                    isLabelVisible:
                        _filterLanguage != null ||
                        _isYearRangeActive(_yearRange),
                    backgroundColor: c.red,
                    child: Icon(Icons.tune_rounded, color: c.ink, size: 20),
                  ),
                  onPressed: _openFilters,
                ),
              ],
      ),
      body: _loading
          ? _skeleton()
          : _hasError && _movies.isEmpty
          ? _error()
          : _movies.isEmpty
          ? _empty()
          : _bodyContent(),
    );
  }

  Widget _bodyContent() {
    final c = context.c;
    final hasActiveFilters =
        _filterLanguage != null || _isYearRangeActive(_yearRange);
    if (!hasActiveFilters) return _grid();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_filterLanguage != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RawChip(
                      label: Text(
                        _getLanguageLabel(
                          _filterLanguage!,
                          _languages
                              .firstWhere((l) => l.code == _filterLanguage)
                              .label,
                        ),
                        style: TextStyle(color: c.ink, fontSize: 12),
                      ),
                      backgroundColor: c.red.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onDeleted: () {
                        setState(() {
                          _filterLanguage = null;
                          _loadFirstPage();
                        });
                      },
                      deleteIconColor: c.dim,
                    ),
                  ),
                if (_isYearRangeActive(_yearRange))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RawChip(
                      label: Text(
                        '${_yearRange.start.round()} - ${_yearRange.end.round()}',
                        style: TextStyle(color: c.ink, fontSize: 12),
                      ),
                      backgroundColor: c.red.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onDeleted: () {
                        setState(() {
                          _yearRange = RangeValues(
                            1970,
                            _currentYear.toDouble(),
                          );
                          _loadFirstPage();
                        });
                      },
                      deleteIconColor: c.dim,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: _grid()),
      ],
    );
  }

  Widget _skeleton() => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.62,
    ),
    itemCount: 6,
    itemBuilder: (_, i) => ResultsSkeletonCard(delay: i * 80),
  );

  Widget _error() {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.red.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.wifi_off_rounded, color: c.red, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)?.get('browse_error') ??
                  'An error occurred',
              style: TextStyle(
                color: c.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppLocalizations.of(context)?.get('browse_conn_error') ??
                    'Connection error. Please check your internet.',
                style: TextStyle(color: c.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _loadFirstPage();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                AppLocalizations.of(context)?.get('browse_retry') ?? 'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.dim.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.search_off_rounded, color: c.dim, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.get('search_no_results') ??
                'Sonuç bulunamadı',
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.get('try_different_filters') ??
                'Try different filters',
            style: TextStyle(color: c.dim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final c = context.c;
    return Stack(
      children: [
        GridView.builder(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: _movies.length,
          itemBuilder: (_, i) => ResultsMovieCard(
            movie: _movies[i],
            onTap: () => _showDetail(_movies[i]),
            jointGenres: widget.jointGenres,
          ),
        ),
        if (_loadingMore)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.red,
                  ),
                ),
              ),
            ),
          ),
      ],
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
