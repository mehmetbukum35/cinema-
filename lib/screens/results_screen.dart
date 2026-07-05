import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'movie_detail_sheet.dart';

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
  Object? _fetchError;

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
      _fetchError = null;
      _movies.clear();
      _seenIds.clear();
      _page = 1;
      _hasMore = true;
    });
    try {
      final batch = await _fetchDiscover(1);
      if (!mounted) return;
      setState(() {
        _movies.addAll(batch.where((m) => _seenIds.add('${m.isTV ? 'tv' : 'movie'}_${m.id}')));
        if (batch.isEmpty) _hasMore = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _fetchError = e;
        _hasMore = false;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final batch = await _fetchDiscover(nextPage);
      if (!mounted) return;
      final fresh = batch.where((m) => _seenIds.add('${m.isTV ? 'tv' : 'movie'}_${m.id}')).toList();
      setState(() {
        _page = nextPage;
        _movies.addAll(fresh);
        // TMDB boş sayfa döndürdüyse veya yeni öğe kalmadıysa dur.
        if (batch.isEmpty) _hasMore = false;
        _loadingMore = false;
      });
    } catch (_) {
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
                    final isTr =
                        AppLocalizations.of(context)?.locale.languageCode ==
                        'tr';
                    final suffix =
                        (tempLang != null ||
                            _isYearRangeActive(tempYear))
                        ? (isTr ? ' (Aktif)' : ' (Active)')
                        : '';
                    return Text(
                      '${isTr ? 'Filtrele' : 'Filter'}$suffix',
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
                        final isTr =
                            AppLocalizations.of(context)?.locale.languageCode ==
                            'tr';
                        return Text(
                          '${isTr ? 'Yıl' : 'Year'}: ${tempYear.start.round()} – ${tempYear.end.round()}',
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
                        final isTr =
                            AppLocalizations.of(context)?.locale.languageCode ==
                            'tr';
                        return Text(
                          isTr ? 'DİL' : 'LANGUAGE',
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
                      final isTr =
                          AppLocalizations.of(context)?.locale.languageCode ==
                          'tr';
                      return _LangChip(
                        label: isTr ? 'Tümü' : 'All',
                        selected: tempLang == null,
                        onTap: () => setModal(() => tempLang = null),
                      );
                    },
                  ),
                  ..._languages.map(
                    (l) => _LangChip(
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
                  ? (AppLocalizations.of(context)?.get('search_trending_shows') ?? 'Trend Diziler')
                  : (AppLocalizations.of(context)?.get('search_trending_movies') ?? 'Trend Filmler'))
              : (AppLocalizations.of(context)?.get('results_title') ?? 'Öneriler'),
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
                          _yearRange = RangeValues(1970, _currentYear.toDouble());
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
    itemBuilder: (_, i) => _SkeletonCard(delay: i * 80),
  );

  Widget _error() {
    final c = context.c;
    final isApiKeyMissing =
        _fetchError != null && (_fetchError.toString().contains('TMDB_API_KEY') || _fetchError.toString().toLowerCase().contains('tmdb_api_key eksik'));
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
              child: Icon(
                isApiKeyMissing
                    ? Icons.vpn_key_off_rounded
                    : Icons.wifi_off_rounded,
                color: c.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isApiKeyMissing
                  ? (AppLocalizations.of(context)?.get('browse_api_missing') ??
                        'Configuration Error')
                  : (AppLocalizations.of(context)?.get('browse_error') ??
                        'An error occurred'),
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
                isApiKeyMissing
                    ? (AppLocalizations.of(
                            context,
                          )?.get('browse_api_missing_desc') ??
                          'Server-side service configuration error. Please try again later.')
                    : (AppLocalizations.of(context)?.get('browse_conn_error') ??
                          'Connection error. Please check your internet.'),
                style: TextStyle(color: c.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            if (!isApiKeyMissing) ...[
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
            AppLocalizations.of(context)?.locale.languageCode == 'tr'
                ? 'Farklı filtreler dene'
                : 'Try different filters',
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
          itemBuilder: (_, i) => _MovieCard(
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

// ─── movie card ──────────────────────────────────────────────────────────────
class _MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final List<int>? jointGenres;

  const _MovieCard({
    required this.movie,
    required this.onTap,
    this.jointGenres,
  });

  int _calculateJointScore(List<int> movieGenreIds, double voteAverage) {
    if (jointGenres == null || jointGenres!.isEmpty) return 0;
    if (movieGenreIds.isEmpty) return 0;
    final common = movieGenreIds.where((id) {
      final mappedId = movie.isTV
          ? (switch (id) {
              10759 => 28,
              10765 => 878,
              10762 => 10751,
              _ => id,
            })
          : id;
      return jointGenres!.contains(mappedId);
    }).length;
    if (common == 0) return 0;
    final double similarity = common / jointGenres!.length;
    final double rawScore = 0.7 * similarity + 0.3 * (voteAverage / 10.0);
    final double z = (rawScore - 0.2) * 4.0;
    final double sigmoid = 1.0 / (1.0 + exp(-z));
    return (40 + (sigmoid * 58)).round().clamp(40, 98);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            movie.posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: movie.posterUrl,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => _placeholder(ctx),
                    errorWidget: (ctx, url, err) => _placeholder(ctx),
                  )
                : _placeholder(context),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      (() {
                        final jointScore = _calculateJointScore(movie.genreIds, movie.voteAverage);
                        if (jointScore > 0) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: c.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt_rounded, color: c.green, size: 13),
                                  const SizedBox(width: 3),
                                  Text(
                                    '%$jointScore',
                                    style: TextStyle(
                                      color: c.green,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      })(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, color: c.gold, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              movie.voteAverage.toStringAsFixed(1),
                              style: TextStyle(
                                color: c.gold,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: (movie.isTV ? const Color(0xFF1565C0) : c.red)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          movie.isTV
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_tv') ??
                                    'Dizi')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_movie') ??
                                    'Film'),
                          style: TextStyle(
                            color: movie.isTV ? const Color(0xFF1565C0) : c.red,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.card,
      child: Center(
        child: Icon(Icons.movie_rounded, color: c.border, size: 40),
      ),
    );
  }
}

// ─── skeleton card ───────────────────────────────────────────────────────────
class _SkeletonCard extends StatefulWidget {
  final int delay;
  const _SkeletonCard({required this.delay});
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween(
      begin: 0.4,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, child) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Color.lerp(context.c.surface, context.c.cardHi, _anim.value),
      ),
    ),
  );
}

// ─── language chip ────────────────────────────────────────────────────────────
class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? c.red.withValues(alpha: 0.15) : c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? c.red : c.border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? c.red : c.dim,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
