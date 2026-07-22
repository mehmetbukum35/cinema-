import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/movie.dart';
import '../../providers/top_list_provider.dart';
import '../../services/providers.dart';
import '../../services/tmdb_service.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../../widgets/search_year_hint.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/cinematic_background.dart';
import '../movie_detail_sheet.dart';
import 'top_rank_badge.dart';

/// Top 20 düzenleme ekranı: Film/Dizi sekmeleri, sürükle-bırak sıralama ve
/// arama ile ekleme. Liste `topListProvider` üzerinden otoritedir.
class TopListEditScreen extends ConsumerStatefulWidget {
  /// 0: Film, 1: Dizi.
  final int initialTab;
  const TopListEditScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<TopListEditScreen> createState() => _TopListEditScreenState();
}

class _TopListEditScreenState extends ConsumerState<TopListEditScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return CinematicBackground(
      animate: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: tr?.get('semantics_go_back') ?? 'Back',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          title: Text(
            tr?.get('top_list_edit_title') ?? "Top 20'ni Düzenle",
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border, width: 1),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tab,
                  indicator: BoxDecoration(
                    color: c.isLight
                        ? c.gold.withValues(alpha: 0.15)
                        : c.cardHi,
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
                      text: tr?.get('top_list_tab_movies') ?? 'Film',
                    ),
                    Tab(height: 38, text: tr?.get('top_list_tab_tv') ?? 'Dizi'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: const [_TopListTab(isTV: false), _TopListTab(isTV: true)],
        ),
      ),
    );
  }
}

class _TopListTab extends ConsumerWidget {
  final bool isTV;
  const _TopListTab({required this.isTV});

  void _openDetail(BuildContext context, WidgetRef ref, Movie movie) {
    final service = ref.read(tmdbServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
  }

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref) async {
    final full =
        (ref.read(topListProvider(isTV)).value ?? const <Movie>[]).length >=
        TopListNotifier.cap;
    if (full) {
      HapticFeedback.mediumImpact();
      showAppToast(
        context,
        AppLocalizations.of(context)?.get('top_list_full') ??
            'Liste dolu (20/20).',
      );
      return;
    }
    HapticFeedback.lightImpact();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSheet(isTV: isTV),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final state = ref.watch(topListProvider(isTV));
    final list = state.value ?? const <Movie>[];
    final canAdd = list.length < TopListNotifier.cap;

    return Column(
      children: [
        // Ekle + sayaç + sürükle ipucu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text(
                '${list.length}/${TopListNotifier.cap}',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (list.length > 1) ...[
                const SizedBox(width: 10),
                Icon(Icons.drag_indicator_rounded, color: c.dim, size: 15),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    tr?.get('top_list_reorder_hint') ?? 'Sürükleyip sırala',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 11.5),
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: canAdd ? () => _openAddSheet(context, ref) : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: canAdd ? c.red.withValues(alpha: 0.14) : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: canAdd ? c.red.withValues(alpha: 0.5) : c.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        color: canAdd ? c.red : c.dim,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        (isTV
                                ? tr?.get('top_list_add_tv')
                                : tr?.get('top_list_add_movie')) ??
                            'Ekle',
                        style: TextStyle(
                          color: canAdd ? c.red : c.dim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.dim),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                AppLocalizations.of(context)?.get('browse_conn_error') ??
                    'Bir hata oluştu.',
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
            ),
            data: (items) => items.isEmpty
                ? _empty(context, ref)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    buildDefaultDragHandles: false,
                    itemCount: items.length,
                    // ignore: deprecated_member_use
                    onReorder: (oldI, newI) {
                      HapticFeedback.mediumImpact();
                      ref
                          .read(topListProvider(isTV).notifier)
                          .reorder(oldI, newI);
                    },
                    itemBuilder: (ctx, i) {
                      final m = items[i];
                      return _EditRow(
                        key: ValueKey('${m.isTV}_${m.id}'),
                        index: i,
                        rank: i + 1,
                        movie: m,
                        onTap: () => _openDetail(context, ref, m),
                        onRemove: () {
                          HapticFeedback.lightImpact();
                          ref.read(topListProvider(isTV).notifier).remove(m.id);
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.emoji_events_rounded, color: c.gold, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              tr?.get('top_list_empty_title') ?? 'Panteonunu oluştur',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr?.get('top_list_empty_desc') ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => _openAddSheet(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: CinemaGradients.crimson,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: CinemaShadows.glow(c.red, strength: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr?.get('top_list_empty_cta') ?? 'Top 20 oluştur',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Düzenleme satırı: sıra rozeti + poster + başlık/yıl + sürükle tutamağı + çıkar.
class _EditRow extends StatelessWidget {
  final int index;
  final int rank;
  final Movie movie;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _EditRow({
    super.key,
    required this.index,
    required this.rank,
    required this.movie,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Tüm satır: basılı tut → sürükle (herhangi bir yerden). Sağdaki tutamak ise
    // anında sürükler; kısa dokunuş yapımın detayını açar.
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              child: Row(
                children: [
                  TopRankBadge(rank: rank, size: 28),
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AppCachedNetworkImage(
                      imageUrl: movie.posterUrl,
                      width: 42,
                      height: 60,
                      fit: BoxFit.cover,
                      preset: AppImageCachePreset.avatar,
                      placeholder: (ctx, url) => ColoredBox(color: c.card),
                      errorWidget: (ctx, url, err) => ColoredBox(color: c.card),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (movie.year.isNotEmpty)
                          Text(
                            movie.year,
                            style: TextStyle(color: c.dim, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.dim, size: 20),
                    tooltip:
                        AppLocalizations.of(context)?.get('top_list_remove') ??
                        'Çıkar',
                    onPressed: onRemove,
                  ),
                  // Anında sürükleme tutamağı — geniş dokunma alanı.
                  ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: c.dim,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Arama ile ekleme sayfası (alt sayfa). searchMulti sonucu `isTV` ile filtrelenir;
/// dokununca `topListProvider`e eklenir.
class _AddSheet extends ConsumerStatefulWidget {
  final bool isTV;
  const _AddSheet({required this.isTV});

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _ctrl = TextEditingController();
  List<Movie> _results = [];
  bool _searching = false;
  bool _failed = false;
  Timer? _debounce;
  int _reqId = 0;

  TmdbService get _service => ref.read(tmdbServiceProvider);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    final reqId = ++_reqId;
    setState(() {});
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _failed = false;
      });
      try {
        final all = await _service.searchMulti(query);
        final res = all.where((m) => m.isTV == widget.isTV).toList();
        if (!mounted || reqId != _reqId) return;
        setState(() {
          _results = res;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || reqId != _reqId) return;
        setState(() {
          _results = [];
          _searching = false;
          _failed = true;
        });
      }
    });
  }

  Future<void> _add(Movie m) async {
    final added = await ref.read(topListProvider(widget.isTV).notifier).add(m);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    if (added) {
      showAppToast(
        context,
        AppLocalizations.of(
              context,
            )?.get('top_list_added').replaceAll('{}', m.title) ??
            '${m.title} eklendi.',
      );
    } else {
      showAppToast(
        context,
        AppLocalizations.of(context)?.get('top_list_full') ??
            'Liste dolu (20/20).',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final selectedIds =
        (ref.watch(topListProvider(widget.isTV)).value ?? const <Movie>[])
            .map((m) => m.id)
            .toSet();
    final full = selectedIds.length >= TopListNotifier.cap;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.dim.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        onChanged: _onSearch,
                        style: TextStyle(color: c.ink, fontSize: 15),
                        decoration: InputDecoration(
                          hintText:
                              (widget.isTV
                                  ? tr?.get('top_list_search_tv_hint')
                                  : tr?.get('top_list_search_movie_hint')) ??
                              (widget.isTV
                                  ? 'Dizi adı + yıl (mesela: Fargo 2014)'
                                  : 'Film adı + yıl (mesela: Dune 1984)'),
                          hintStyle: TextStyle(color: c.dim),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: c.dim,
                            size: 20,
                          ),
                          suffixIcon: _ctrl.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: c.dim,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _ctrl.clear();
                                    setState(() {
                                      _reqId++;
                                      _results = [];
                                      _searching = false;
                                      _failed = false;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    const SearchYearHint(),
                  ],
                ),
              ),
              if (full)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    tr?.get('top_list_full') ?? 'Liste dolu (20/20).',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: _searching
                    ? Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.dim,
                          ),
                        ),
                      )
                    : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _failed
                                ? (tr?.get('onboarding_search_error') ??
                                      'Arama başarısız. Tekrar deneyin.')
                                : _ctrl.text.isEmpty
                                ? (tr?.get('top_list_search_prompt') ??
                                      'Eklemek istediğiniz yapımı arayın.')
                                : (tr?.get('search_no_results') ?? ''),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.dim,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _results.length,
                        itemBuilder: (ctx, i) {
                          final m = _results[i];
                          final sel = selectedIds.contains(m.id);
                          final disabled = !sel && full;
                          return Opacity(
                            opacity: disabled ? 0.4 : 1,
                            child: GestureDetector(
                              onTap: (sel || disabled) ? null : () => _add(m),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? c.red.withValues(alpha: 0.1)
                                      : c.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: sel ? c.red : c.border,
                                    width: sel ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                            left: Radius.circular(9),
                                          ),
                                      child: AppCachedNetworkImage(
                                        imageUrl: m.posterUrl,
                                        width: 44,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        preset: AppImageCachePreset.avatar,
                                        placeholder: (ctx, url) =>
                                            ColoredBox(color: c.card),
                                        errorWidget: (ctx, url, err) =>
                                            ColoredBox(color: c.card),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.ink,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (m.year.isNotEmpty)
                                            Text(
                                              m.year,
                                              style: TextStyle(
                                                color: c.dim,
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Icon(
                                        sel
                                            ? Icons.check_circle_rounded
                                            : Icons.add_circle_outline_rounded,
                                        color: sel ? c.red : c.dim,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
