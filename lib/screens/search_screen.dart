import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/pulsing_placeholder.dart';
import 'movie_detail_sheet.dart';
import 'results_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  TmdbService get _service => ref.read(tmdbServiceProvider);
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Movie> _results = [];
  List<String> _history = [];
  bool _searching = false;
  String _lastQuery = '';
  bool _hasError = false;

  String? _selectedLanguage;
  int? _selectedProvider;
  double? _selectedMinRating;

  @override
  void initState() {
    super.initState();
    PrefsService.getSearchHistory().then((h) {
      if (mounted) setState(() => _history = h);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
        _lastQuery = '';
        _hasError = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      if (!mounted) return;
      _lastQuery = q;
      setState(() {
        _searching = true;
        _hasError = false;
      });
      try {
        final results = await _service.searchMulti(q);
        if (!mounted || q != _lastQuery) return;
        await PrefsService.addSearchHistory(q.trim());
        final history = await PrefsService.getSearchHistory();
        if (!mounted) return;
        setState(() {
          _results = results;
          _searching = false;
          _history = history;
        });
      } catch (e) {
        if (!mounted || q != _lastQuery) return;
        setState(() {
          _results = [];
          _searching = false;
          _hasError = true;
        });
      }
    });
  }

  void _searchFromHistory(String q) {
    HapticFeedback.lightImpact();
    _ctrl.text = q;
    _search(q);
  }

  Future<void> _clearHistory() async {
    HapticFeedback.mediumImpact();
    await PrefsService.clearSearchHistory();
    if (mounted) setState(() => _history = []);
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CinematicBackground(
      animate: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header + search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.get('tab_search') ?? 'Ara',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: c.isLight
                                  ? Border.all(color: c.border, width: 1)
                                  : null,
                            ),
                            child: TextField(
                              controller: _ctrl,
                              onChanged: _search,
                              autofocus: false,
                              style: TextStyle(color: c.ink, fontSize: 15),
                              decoration: InputDecoration(
                                hintText:
                                    AppLocalizations.of(
                                      context,
                                    )?.get('search_hint') ??
                                    'Film veya dizi adı...',
                                hintStyle: TextStyle(
                                  color: c.dim,
                                  fontSize: 15,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: c.dim,
                                  size: 20,
                                ),
                                suffixIcon: _ctrl.text.isNotEmpty
                                    ? Tooltip(
                                        message:
                                            AppLocalizations.of(
                                              context,
                                            )?.get('semantics_close') ??
                                            'Close',
                                        child: Semantics(
                                          button: true,
                                          label:
                                              AppLocalizations.of(
                                                context,
                                              )?.get('semantics_close') ??
                                              'Close',
                                          child: GestureDetector(
                                            onTap: () {
                                              HapticFeedback.lightImpact();
                                              _ctrl.clear();
                                              setState(() {
                                                _results = [];
                                                _lastQuery = '';
                                              });
                                            },
                                            child: Icon(
                                              Icons.close_rounded,
                                              color: c.dim,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Tooltip(
                          message:
                              AppLocalizations.of(context)?.get('filter') ??
                              'Filter',
                          child: Semantics(
                            button: true,
                            label:
                                AppLocalizations.of(context)?.get('filter') ??
                                'Filter',
                            child: GestureDetector(
                              onTap: () => _showSearchFilterSheet(context),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        (_selectedLanguage != null ||
                                            _selectedProvider != null ||
                                            _selectedMinRating != null)
                                        ? c.red
                                        : (c.isLight
                                              ? c.border
                                              : Colors.transparent),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.tune_rounded,
                                  color:
                                      (_selectedLanguage != null ||
                                          _selectedProvider != null ||
                                          _selectedMinRating != null)
                                      ? c.red
                                      : c.dim,
                                  size: 20,
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
              // Results
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.c;
    if (_searching) return _skeletonLoader();
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: c.red, size: 40),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)?.get('search_failed') ??
                  'Arama başarısız oldu',
              style: TextStyle(
                color: c.ink,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                AppLocalizations.of(context)?.get('browse_conn_error') ??
                    'Bağlantınızı kontrol edip tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _search(_ctrl.text);
              },
              child: Text(
                AppLocalizations.of(context)?.get('browse_retry') ??
                    'Yeniden Dene',
                style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
    if (_ctrl.text.isEmpty) return _quickAccess();
    if (_results.isEmpty && _lastQuery.length >= 2) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('search_no_results') ??
              'Sonuç bulunamadı',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
      );
    }
    return _resultsList();
  }

  Widget _skeletonLoader() {
    final c = context.c;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (ctx, i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const SizedBox(
                  width: 44,
                  height: 64,
                  child: PulsingPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 30,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.dim, size: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _quickAccess() {
    final c = context.c;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  AppLocalizations.of(context)?.get('search_history') ??
                      'Son Aramalar',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearHistory,
                  child: Text(
                    AppLocalizations.of(context)?.get('search_clear') ??
                        'Temizle',
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._history.map(
              (q) => GestureDetector(
                onTap: () => _searchFromHistory(q),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: c.dim, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          q,
                          style: TextStyle(color: c.ink, fontSize: 14),
                        ),
                      ),
                      Icon(Icons.north_west_rounded, color: c.dim, size: 14),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            AppLocalizations.of(context)?.get('search_quick_search') ?? '',
            style: TextStyle(
              color: c.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _QuickTile(
            icon: Icons.local_fire_department_rounded,
            color: c.red,
            label:
                AppLocalizations.of(context)?.get('search_trending_movies') ??
                '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ResultsScreen(includeTv: false, isTrending: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickTile(
            icon: Icons.tv_rounded,
            color: c.blue,
            label:
                AppLocalizations.of(context)?.get('search_trending_shows') ??
                '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ResultsScreen(includeMovies: false, isTrending: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickTile(
            icon: Icons.star_rounded,
            color: c.gold,
            label: AppLocalizations.of(context)?.get('browse_top_rated') ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ResultsScreen(
                  minRating: 8.0,
                  sortBy: 'vote_average.desc',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickTile(
            icon: Icons.new_releases_rounded,
            color: Colors.green,
            label:
                AppLocalizations.of(context)?.get('search_new_releases') ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ResultsScreen(
                  sortBy: 'primary_release_date.desc',
                  includeTv: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pull-to-refresh: mevcut sorguyu debounce'suz yeniden çalıştırır (awaitable).
  Future<void> _refreshSearch() async {
    final q = _lastQuery;
    if (q.trim().length < 2) return;
    setState(() {
      _searching = true;
      _hasError = false;
    });
    try {
      final results = await _service.searchMulti(q);
      if (!mounted || q != _lastQuery) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _hasError = true;
      });
    }
  }

  Widget _resultsList() {
    final c = context.c;
    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: _refreshSearch,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _results.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final m = _results[i];
          return GestureDetector(
            onTap: () => _openDetail(m),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 58,
                      height: 84,
                      child: m.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: m.posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  ColoredBox(color: c.border),
                              errorWidget: (context, url, error) =>
                                  ColoredBox(color: c.border),
                            )
                          : ColoredBox(color: c.border),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: (m.isTV ? c.blue : c.red).withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m.isTV
                                    ? (AppLocalizations.of(
                                            context,
                                          )?.get('onboarding_tv') ??
                                          'Dizi')
                                    : (AppLocalizations.of(
                                            context,
                                          )?.get('onboarding_movie') ??
                                          'Film'),
                                style: TextStyle(
                                  color: m.isTV ? c.blue : c.red,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (m.year.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                m.year,
                                style: TextStyle(color: c.dim, fontSize: 13),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Icon(Icons.star_rounded, color: c.gold, size: 13.5),
                            const SizedBox(width: 2),
                            Text(
                              m.voteAverage.toStringAsFixed(1),
                              style: TextStyle(
                                color: c.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MovieDetailSheet.confirmBlockMovie(
                        context: context,
                        ref: ref,
                        movie: m,
                        onBlocked: () {
                          setState(() {
                            _results.removeAt(i);
                          });
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.visibility_off_rounded,
                        color: c.dim,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Map<String, String> _getLanguages(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return {
      'ko': localizations?.get('lang_ko') ?? 'Kore Sineması',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl':
          localizations?.get('lang_eu') ?? 'Avrupa Sineması',
      'en': localizations?.get('lang_en') ?? 'Hollywood',
      'tr': localizations?.get('lang_tr') ?? 'Türk Sineması',
      'ja': localizations?.get('lang_ja') ?? 'Japon Sineması',
      'hi': localizations?.get('lang_hi') ?? 'Bollywood',
    };
  }

  static String _getLanguageLabel(BuildContext context, String lang) {
    return _getLanguages(context)[lang] ?? lang;
  }

  static const _providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime Video',
    337: 'Disney+',
  };

  static final _ratings = {6.0: '6.0+', 7.0: '7.0+', 7.5: '7.5+', 8.0: '8.0+'};

  void _showSearchFilterSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    String? localLang = _selectedLanguage;
    int? localProv = _selectedProvider;
    double? localRating = _selectedMinRating;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final c = ctx.c;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.bg.withValues(alpha: c.isLight ? 0.96 : 0.85),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border.all(
                    color: c.isLight
                        ? c.border
                        : Colors.white.withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Builder(
                          builder: (context) {
                            return Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('advanced_filters') ??
                                  'Advanced Filters',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        if (localLang != null ||
                            localProv != null ||
                            localRating != null)
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                localLang = null;
                                localProv = null;
                                localRating = null;
                              });
                            },
                            child: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('search_clear') ??
                                  'Temizle',
                              style: TextStyle(
                                color: c.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context)?.get('country_region') ??
                              'COUNTRY / REGION',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return _filterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  (AppLocalizations.of(
                                        context,
                                      )?.get('lang_all') ??
                                      'All'),
                              selected: localLang == null,
                              onTap: () =>
                                  setModalState(() => localLang = null),
                            );
                          },
                        ),
                        ..._getLanguages(context).entries.map((entry) {
                          return _filterChip(
                            label: _getLanguageLabel(context, entry.key),
                            selected: localLang == entry.key,
                            onTap: () =>
                                setModalState(() => localLang = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context)?.get('platform') ??
                              'PLATFORM',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return _filterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  'All',
                              selected: localProv == null,
                              onTap: () =>
                                  setModalState(() => localProv = null),
                            );
                          },
                        ),
                        ..._providers.entries.map((entry) {
                          return _filterChip(
                            label: entry.value,
                            selected: localProv == entry.key,
                            onTap: () =>
                                setModalState(() => localProv = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(
                                context,
                              )?.get('minimum_tmdb_score') ??
                              'MINIMUM TMDB SCORE',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return _filterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  'All',
                              selected: localRating == null,
                              onTap: () =>
                                  setModalState(() => localRating = null),
                            );
                          },
                        ),
                        ..._ratings.entries.map((entry) {
                          return _filterChip(
                            label: entry.value,
                            selected: localRating == entry.key,
                            onTap: () =>
                                setModalState(() => localRating = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 30),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _selectedLanguage = localLang;
                          _selectedProvider = localProv;
                          _selectedMinRating = localRating;
                        });
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ResultsScreen(
                              originalLanguage: _selectedLanguage,
                              providerId: _selectedProvider,
                              minRating: _selectedMinRating,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.red, Color(0xFFB83050)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Builder(
                          builder: (context) {
                            return Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('filter_and_list') ??
                                  'Filter and List',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.red.withValues(alpha: 0.15) : c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c.red : c.border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c.red : c.dim,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(10),
          border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: c.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: c.textFaint, size: 18),
          ],
        ),
      ),
    );
  }
}
