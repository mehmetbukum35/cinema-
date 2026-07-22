import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import 'movie_detail_sheet.dart';
import 'search/widgets/filter_sheet.dart';
import 'search/widgets/input_bar.dart';
import 'search/widgets/quick_access.dart';
import 'search/widgets/results_list.dart';
import 'search/widgets/skeleton_loader.dart';

@visibleForTesting
bool isCurrentSearchRequest({
  required int requestId,
  required int currentRequestId,
  required String query,
  required String currentQuery,
}) => requestId == currentRequestId && query == currentQuery;

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
  int _searchRequestId = 0;

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
    final requestId = ++_searchRequestId;
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
        if (!mounted || requestId != _searchRequestId) return;
        await PrefsService.addSearchHistory(q.trim());
        final history = await PrefsService.getSearchHistory();
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _results = results;
          _searching = false;
          _history = history;
        });
      } catch (e) {
        if (!mounted || requestId != _searchRequestId) return;
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

  void _openFilters() {
    SearchFilterSheet.show(
      context,
      selectedLanguage: _selectedLanguage,
      selectedProvider: _selectedProvider,
      selectedMinRating: _selectedMinRating,
      onApply: (language, provider, minRating) {
        setState(() {
          _selectedLanguage = language;
          _selectedProvider = provider;
          _selectedMinRating = minRating;
        });
      },
    );
  }

  Future<void> _refreshSearch() async {
    final q = _lastQuery;
    if (q.trim().length < 2) return;
    final requestId = ++_searchRequestId;
    setState(() {
      _searching = true;
      _hasError = false;
    });
    try {
      final results = await _service.searchMulti(q);
      if (!mounted ||
          !isCurrentSearchRequest(
            requestId: requestId,
            currentRequestId: _searchRequestId,
            query: q,
            currentQuery: _lastQuery,
          )) {
        return;
      }
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted ||
          !isCurrentSearchRequest(
            requestId: requestId,
            currentRequestId: _searchRequestId,
            query: q,
            currentQuery: _lastQuery,
          )) {
        return;
      }
      setState(() {
        _results = [];
        _searching = false;
        _hasError = true;
      });
    }
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
              SearchInputBar(
                controller: _ctrl,
                onChanged: _search,
                onClear: () {
                  _ctrl.clear();
                  setState(() {
                    _results = [];
                    _lastQuery = '';
                  });
                },
                onOpenFilters: _openFilters,
                hasActiveFilters:
                    _selectedLanguage != null ||
                    _selectedProvider != null ||
                    _selectedMinRating != null,
              ),
              Expanded(child: _body(c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemePalette c) {
    if (_searching) return const SearchSkeletonLoader();
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
    if (_ctrl.text.isEmpty) {
      return SearchQuickAccess(
        history: _history,
        onClearHistory: _clearHistory,
        onSearchFromHistory: _searchFromHistory,
      );
    }
    if (_results.isEmpty && _lastQuery.length >= 2) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('search_no_results') ??
              'Sonuç bulunamadı',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
      );
    }
    return SearchResultsList(
      results: _results,
      onRefresh: _refreshSearch,
      onOpenDetail: _openDetail,
      onBlockMovie: (index) {
        setState(() {
          _results.removeAt(index);
        });
      },
    );
  }
}
