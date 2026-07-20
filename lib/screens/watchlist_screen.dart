import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../providers/watchlist_provider.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/app_cached_image.dart';
import '../widgets/pulsing_placeholder.dart';
import '../widgets/entrance.dart';
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

enum _TypeFilter { all, movie, tv }

enum _Sort { added, rating, year, myRating }

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  _TypeFilter _type = _TypeFilter.all;
  _Sort _sort = _Sort.added;

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
          if (_tabController.index == 0 && _sort == _Sort.myRating) {
            _sort = _Sort.added;
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
    _TypeFilter.all => true,
    _TypeFilter.movie => !m.isTV,
    _TypeFilter.tv => m.isTV,
  };

  int _yearOf(Movie m) => int.tryParse(m.year) ?? 0;

  List<Movie> _applyWatchlist(List<Movie> list) {
    final out = list.where(_passesType).toList();
    switch (_sort) {
      case _Sort.rating:
        out.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      case _Sort.year:
        out.sort((a, b) => _yearOf(b).compareTo(_yearOf(a)));
      case _Sort.added:
      case _Sort.myRating:
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
      case _Sort.rating:
        out.sort(
          (a, b) => (b['movie'] as Movie).voteAverage.compareTo(
            (a['movie'] as Movie).voteAverage,
          ),
        );
      case _Sort.year:
        out.sort(
          (a, b) => _yearOf(
            b['movie'] as Movie,
          ).compareTo(_yearOf(a['movie'] as Movie)),
        );
      case _Sort.myRating:
        out.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
      case _Sort.added:
        break;
    }
    return out;
  }

  String _sortLabel(AppLocalizations? tr, _Sort s) => switch (s) {
    _Sort.added => tr?.get('sort_added') ?? 'Eklenme',
    _Sort.rating => tr?.get('sort_rating') ?? 'Puan',
    _Sort.year => tr?.get('sort_year') ?? 'Yıl',
    _Sort.myRating => tr?.get('sort_my_rating') ?? 'Puanım',
  };

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
            _segmentedTabs(c, tr, watchlist.length, rated.length),
            _filterRow(c, tr),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  watchlistState.when(
                    loading: () => _loadingSkeleton(),
                    error: (err, st) => _errorScreen(context),
                    data: (list) {
                      final filtered = _applyWatchlist(list);
                      return filtered.isEmpty
                          ? _emptyWatchlist(context)
                          : _watchlistGrid(filtered);
                    },
                  ),
                  statsState.when(
                    loading: () => _loadingSkeleton(),
                    error: (err, st) => _errorScreen(context),
                    data: (stats) {
                      final filtered = _applyRated(
                        (stats['ratedMovies'] as List<dynamic>?) ?? const [],
                      );
                      return filtered.isEmpty
                          ? _emptyRated(context)
                          : _ratedGrid(filtered);
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

  // ── Üst kontroller ─────────────────────────────────────────────────────

  Widget _segmentedTabs(
    ThemePalette c,
    AppLocalizations? tr,
    int watchCount,
    int ratedCount,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 1),
        ),
        padding: const EdgeInsets.all(3),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: c.isLight ? c.gold.withValues(alpha: 0.15) : c.cardHi,
            borderRadius: BorderRadius.circular(9),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: c.gold,
          unselectedLabelColor: c.dim,
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            Tab(
              height: 38,
              text:
                  '${tr?.get('profile_watchlist') ?? 'İzleme Listesi'} · $watchCount',
            ),
            Tab(
              height: 38,
              text:
                  '${tr?.get('profile_history') ?? 'Değerlendirdiklerim'} · $ratedCount',
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterRow(ThemePalette c, AppLocalizations? tr) {
    Widget chip(String label, _TypeFilter value) {
      final on = _type == value;
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _type = value);
        },
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.red.withValues(alpha: 0.15) : c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? c.red : c.border, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? c.red : c.dim,
              fontSize: 12,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final sorts = [
      _Sort.added,
      _Sort.rating,
      _Sort.year,
      if (_tabController.index == 1) _Sort.myRating,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip(tr?.get('lang_all') ?? 'Tümü', _TypeFilter.all),
          chip(tr?.get('onboarding_movie') ?? 'Film', _TypeFilter.movie),
          chip(tr?.get('onboarding_tv') ?? 'Dizi', _TypeFilter.tv),
          const Spacer(),
          PopupMenuButton<_Sort>(
            tooltip: tr?.get('sort_added') ?? 'Sırala',
            onSelected: (s) {
              HapticFeedback.lightImpact();
              setState(() => _sort = s);
            },
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (ctx) => [
              for (final s in sorts)
                PopupMenuItem(
                  value: s,
                  height: 40,
                  child: Row(
                    children: [
                      Icon(
                        _sort == s
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 16,
                        color: _sort == s ? c.gold : c.dim,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _sortLabel(tr, s),
                        style: TextStyle(
                          color: _sort == s ? c.ink : c.dim,
                          fontSize: 13.5,
                          fontWeight: _sort == s
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, color: c.gold, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    _sortLabel(tr, _sort),
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Grid'ler ───────────────────────────────────────────────────────────

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 0.62,
  );

  Widget _loadingSkeleton() => GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    gridDelegate: _gridDelegate,
    itemCount: 9,
    itemBuilder: (ctx, i) => ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: const PulsingPlaceholder(),
    ),
  );

  Widget _watchlistGrid(List<Movie> items) {
    final c = context.c;
    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: () => ref.read(watchlistProvider.notifier).load(),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: _gridDelegate,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final m = items[i];
          return GestureDetector(
            onTap: () => _openDetail(m),
            onLongPress: () => _confirmRemove(m),
            child: _posterCell(
              m,
              footer: Row(
                children: [
                  Icon(Icons.star_rounded, color: c.gold, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    m.voteAverage.toStringAsFixed(1),
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

  Widget _ratedGrid(List<Map<String, dynamic>> items) {
    final c = context.c;
    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: () => ref.read(statsProvider.notifier).load(),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: _gridDelegate,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final m = item['movie'] as Movie;
          final rating = (item['rating'] as int).clamp(0, 3);
          final isPrivate = (item['is_private'] as int? ?? 0) == 1;
          final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
          final ratingLabelKey = [
            'profile_berbat',
            'profile_eh',
            'profile_iyi',
            'profile_harika',
          ][rating];
          final ratingLabel =
              AppLocalizations.of(context)?.get(ratingLabelKey) ??
              const ['Berbat', 'Eh', 'İyi', 'Harika'][rating];

          return GestureDetector(
            onTap: () => _openDetail(m),
            onLongPress: () => _confirmDeleteRating(m),
            child: _posterCell(
              m,
              topLeft: isPrivate
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      child: Icon(Icons.lock_rounded, color: c.gold, size: 12),
                    )
                  : null,
              footer: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ratingColors[rating].withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ratingLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Ortak grid hücresi: poster + alt gradyan + başlık + footer rozeti.
  Widget _posterCell(Movie m, {Widget? footer, Widget? topLeft}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppCachedNetworkImage(
            imageUrl: m.posterUrl,
            fit: BoxFit.cover,
            preset: AppImageCachePreset.poster,
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          if (topLeft != null) Positioned(top: 5, left: 5, child: topLeft),
          Positioned(
            left: 7,
            right: 7,
            bottom: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 4), footer],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Boş / hata durumları ───────────────────────────────────────────────

  Widget _emptyWatchlist(BuildContext context) {
    final c = context.c;
    return _emptyState(
      c,
      icon: Icons.bookmark_border_rounded,
      title: AppLocalizations.of(context)?.get('watchlist_empty_title') ?? '',
      desc: AppLocalizations.of(context)?.get('watchlist_empty_desc') ?? '',
    );
  }

  Widget _emptyRated(BuildContext context) {
    final c = context.c;
    return _emptyState(
      c,
      icon: Icons.star_border_rounded,
      title:
          AppLocalizations.of(context)?.get('library_rated_empty_title') ??
          'Henüz değerlendirme yok',
      desc:
          AppLocalizations.of(context)?.get('library_rated_empty_desc') ??
          'Film ve dizileri puanladıkça geçmişin burada birikir.',
    );
  }

  Widget _emptyState(
    ThemePalette c, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
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
            child: Icon(icon, color: c.dim, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorScreen(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: c.red, size: 48),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(
                  context,
                )?.get('an_error_occurred_while_loadin') ??
                'An error occurred while loading.',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.get('browse_conn_error') ??
                'İnternet bağlantınızı kontrol edip tekrar deneyin.',
            style: TextStyle(color: c.dim, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.invalidate(watchlistProvider);
              ref.invalidate(statsProvider);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)?.get('browse_retry') ?? '',
            ),
          ),
        ],
      ),
    );
  }

  // ── İşlemler ───────────────────────────────────────────────────────────

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
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Vazgeç',
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
      showAppSnackBar(
        context,
        AppLocalizations.of(
              context,
            )?.get('title_removed_from_watchlist').replaceAll('{}', m.title) ??
            '${m.title} removed from watchlist.',
        duration: const Duration(seconds: 3),
        actionLabel: AppLocalizations.of(context)?.get('undo') ?? 'Undo',
        onAction: () => ref.read(watchlistProvider.notifier).add(m),
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
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Vazgeç',
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
      final ratingRecord = await PrefsService.getRating(movie.id, movie.isTV);
      final prevRating = ratingRecord?['rating'] as int?;
      await PrefsService.deleteRating(movie.id, movie.isTV);
      if (prevRating != null) {
        PrefsService.revertRecoOutcome(
          source: movie.recoSource ?? 'discover',
          liked: prevRating >= 2,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
      ref.invalidate(statsProvider);
    }
  }
}
