import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../providers/watchlist_provider.dart';
import '../services/prefs/library_facade.dart';
import '../services/prefs/taste_prefs.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/entrance.dart';
import 'library/library_empty_error.dart';
import 'library/library_filters.dart';
import 'library/library_grids.dart';
import 'movie_detail_sheet.dart';

/// Kütüphane "showroom"u: İzleme Listesi + Değerlendirdiklerim tek tam ekran
/// sayfada, sekmeli grid olarak. Profildeki raylar 10'luk vitrine indirildi;
/// arşivin tamamı (200+ öğe) burada taranır — Film/Dizi filtresi ve sıralama
/// ile gezinme aramaya dönüşür.
class LibraryScreen extends ConsumerStatefulWidget {
  /// 0: İzleme Listesi, 1: Değerlendirdiklerim.
  final int initialTab;
  final bool isActive;
  const LibraryScreen({super.key, this.initialTab = 0, this.isActive = true});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LibraryTypeFilter _type = LibraryTypeFilter.all;
  LibrarySort _sort = LibrarySort.added;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    // Sekme değişince başlık sayacı ve sıralama menüsü güncellensin.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // "Puanım" yalnız Değerlendirdiklerim'de anlamlı.
          if (_tabController.index == 0 && _sort == LibrarySort.myRating) {
            _sort = LibrarySort.added;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    final service = ref.read(tmdbServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
  }

  bool _passesType(Movie m) => switch (_type) {
    LibraryTypeFilter.all => true,
    LibraryTypeFilter.movie => !m.isTV,
    LibraryTypeFilter.tv => m.isTV,
  };

  int _yearOf(Movie m) => int.tryParse(m.year) ?? 0;

  List<Movie> _applyWatchlist(List<Movie> list) {
    final out = list.where(_passesType).toList();
    switch (_sort) {
      case LibrarySort.rating:
        out.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      case LibrarySort.year:
        out.sort((a, b) => _yearOf(b).compareTo(_yearOf(a)));
      case LibrarySort.added:
      case LibrarySort.myRating:
        break; // eklenme sırası (varsayılan liste sırası)
    }
    return out;
  }

  List<Map<String, dynamic>> _applyRated(List<dynamic> rated) {
    final out = rated
        .cast<Map<String, dynamic>>()
        .where((e) => _passesType(e['movie'] as Movie))
        .toList();
    switch (_sort) {
      case LibrarySort.rating:
        out.sort(
          (a, b) => (b['movie'] as Movie).voteAverage.compareTo(
            (a['movie'] as Movie).voteAverage,
          ),
        );
      case LibrarySort.year:
        out.sort(
          (a, b) => _yearOf(
            b['movie'] as Movie,
          ).compareTo(_yearOf(a['movie'] as Movie)),
        );
      case LibrarySort.myRating:
        out.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
      case LibrarySort.added:
        break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final watchlistState = ref.watch(watchlistProvider);
    final statsState = ref.watch(statsProvider);

    final watchlist = watchlistState.value ?? const <Movie>[];
    final rated =
        (statsState.value?['ratedMovies'] as List<dynamic>?) ?? const [];

    final activeCount = _tabController.index == 0
        ? watchlist.length
        : rated.length;

    return CinematicBackground(
      animate: widget.isActive,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip:
                AppLocalizations.of(context)?.get('semantics_go_back') ??
                'Back',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntranceFade(
                child: Text(
                  tr?.get('library_title') ?? 'Kütüphanen',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$activeCount ${tr?.get('watchlist_items') ?? 'öğe'}',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            LibrarySegmentedTabs(
              tabController: _tabController,
              watchCount: watchlist.length,
              ratedCount: rated.length,
            ),
            LibraryFilterRow(
              tabController: _tabController,
              type: _type,
              sort: _sort,
              onTypeChanged: (value) => setState(() => _type = value),
              onSortChanged: (value) => setState(() => _sort = value),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  watchlistState.when(
                    loading: () => const LibraryLoadingSkeleton(),
                    error: (err, st) => LibraryErrorView(
                      onRetry: () {
                        ref.invalidate(watchlistProvider);
                        ref.invalidate(statsProvider);
                      },
                    ),
                    data: (list) {
                      final filtered = _applyWatchlist(list);
                      return filtered.isEmpty
                          ? const LibraryEmptyWatchlist()
                          : LibraryWatchlistGrid(
                              items: filtered,
                              onOpen: _openDetail,
                              onLongPressRemove: _confirmRemove,
                              onRefresh: () =>
                                  ref.read(watchlistProvider.notifier).load(),
                            );
                    },
                  ),
                  statsState.when(
                    loading: () => const LibraryLoadingSkeleton(),
                    error: (err, st) => LibraryErrorView(
                      onRetry: () {
                        ref.invalidate(watchlistProvider);
                        ref.invalidate(statsProvider);
                      },
                    ),
                    data: (stats) {
                      final filtered = _applyRated(
                        (stats['ratedMovies'] as List<dynamic>?) ?? const [],
                      );
                      return filtered.isEmpty
                          ? const LibraryEmptyRated()
                          : LibraryRatedGrid(
                              items: filtered,
                              onOpen: _openDetail,
                              onLongPressDelete: _confirmDeleteRating,
                              onRefresh: () =>
                                  ref.read(statsProvider.notifier).load(),
                            );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(Movie m) async {
    final c = context.c;
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          m.title,
          style: TextStyle(
            color: c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('remove_from_watchlist') ??
              'Remove from watchlist?',
          style: TextStyle(color: c.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(ctx, false);
            },
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Cancel',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx, true);
            },
            child: Text(
              AppLocalizations.of(context)?.get('remove') ?? 'Remove',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(watchlistProvider.notifier).remove(m.id, m.isTV);
      if (!mounted) return;
      final notifier = ref.read(watchlistProvider.notifier);
      showAppSnackBar(
        context,
        AppLocalizations.of(
              context,
            )?.get('title_removed_from_watchlist').replaceAll('{}', m.title) ??
            '${m.title} removed from watchlist.',
        duration: const Duration(seconds: 3),
        actionLabel: AppLocalizations.of(context)?.get('undo') ?? 'Undo',
        onAction: () => notifier.add(m),
      );
    }
  }

  Future<void> _confirmDeleteRating(Movie movie) async {
    final c = context.c;
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          movie.title,
          style: TextStyle(
            color: c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('do_you_want_to_delete_this_rat') ??
              'Do you want to delete this rating and remove it from your history?',
          style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(ctx, false);
            },
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Cancel',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx, true);
            },
            child: Text(
              AppLocalizations.of(context)?.get('delete') ?? 'Delete',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      final ratingRecord = await PrefsLibraryFacade.getRating(
        movie.id,
        movie.isTV,
      );
      final prevRating = ratingRecord?['rating'] as int?;
      await PrefsLibraryFacade.deleteRating(movie.id, movie.isTV);
      if (prevRating != null) {
        PrefsTastePrefs.revertRecoOutcome(
          source: movie.recoSource ?? 'discover',
          liked: prevRating >= 2,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
      ref.invalidate(statsProvider);
    }
  }
}
