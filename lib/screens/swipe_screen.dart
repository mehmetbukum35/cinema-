import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/providers.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../providers/swipe_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/pulsing_placeholder.dart';
import '../widgets/cinematic_background.dart';
import 'movie_detail_sheet.dart';
import '../widgets/spring_button.dart';
class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends ConsumerState<SwipeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  double _dragX = 0.0;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _checkGuide();

    // Start animation on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeCtrl.forward();
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(socialProvider.notifier).loadFriendSignals();
      }
    });
  }

  Future<void> _checkGuide() async {
    final shown = await PrefsService.isSwipeGuideShown();
    if (!shown && mounted) {
      setState(() => _showGuide = true);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _rate(int rating) async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(swipeProvider.notifier);
    final disableAnims =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnims) {
      await notifier.rate(rating);
      return;
    }
    await _fadeCtrl.reverse();
    await notifier.rate(rating);
    if (!mounted) return;
    _fadeCtrl.forward();
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

  Future<void> _undo() async {
    final state = ref.read(swipeProvider);
    if (state.current == 0) return;
    HapticFeedback.lightImpact();
    final notifier = ref.read(swipeProvider.notifier);
    final disableAnims =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnims) {
      await notifier.undo();
      return;
    }
    await _fadeCtrl.reverse();
    await notifier.undo();
    if (!mounted) return;
    _fadeCtrl.forward();
  }

  Map<String, String> _getLanguages(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return {
      'ko': localizations?.get('lang_ko') ?? 'Kore Sineması',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl': localizations?.get('lang_eu') ?? 'Avrupa Sineması',
      'en': localizations?.get('lang_en') ?? 'Hollywood',
      'tr': localizations?.get('lang_tr') ?? 'Türk Sineması',
      'ja': localizations?.get('lang_ja') ?? 'Japon Sineması',
      'hi': localizations?.get('lang_hi') ?? 'Bollywood',
    };
  }

  static const _providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime Video',
    337: 'Disney+',
  };

  String _getLanguageLabel(BuildContext context, String? lang) {
    if (lang == null) return AppLocalizations.of(context)?.get('lang_all') ?? 'Tümü';
    return _getLanguages(context)[lang] ?? (AppLocalizations.of(context)?.get('lang_unknown') ?? 'Bilinmeyen');
  }

  String _getProviderLabel(BuildContext context, int? providerId) {
    final localizations = AppLocalizations.of(context);
    final isTr = localizations?.locale.languageCode == 'tr';
    if (providerId == null) return localizations?.get('lang_all') ?? (isTr ? 'Tümü' : 'All');
    return _providers[providerId] ?? (localizations?.get('lang_unknown') ?? (isTr ? 'Bilinmeyen' : 'Unknown'));
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref, SwipeState state) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final c = context.c;
            final activeLang = state.languageFilter;
            final activeProv = state.providerFilter;

            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: (c.isLight ? c.surface : const Color(0xFF161616))
                        .withValues(alpha: c.isLight ? 0.94 : 0.85),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: c.isLight ? c.border : Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              final isTr =
                                  AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr';
                              final activeCount =
                                  (activeLang != null ? 1 : 0) +
                                  (activeProv != null ? 1 : 0);
                              final filterTitle = isTr
                                  ? 'İçerik Filtreleri'
                                  : 'Content Filters';
                              final activeText = activeCount > 0
                                  ? (isTr
                                        ? ' ($activeCount Aktif)'
                                        : ' ($activeCount Active)')
                                  : '';
                              return Text(
                                '$filterTitle$activeText',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                          const Spacer(),
                          if (activeLang != null || activeProv != null)
                            TextButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: null,
                                      providerFilter: null,
                                    );
                                Navigator.pop(ctx);
                              },
                              child: Text(
                                AppLocalizations.of(ctx)?.get('search_clear') ??
                                    'Temizle',
                                style: TextStyle(
                                  color: c.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              final isTr =
                                  AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr';
                              return Text(
                                isTr ? 'DİL / ÜLKE' : 'LANGUAGE / REGION',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                          if (activeLang != null) ...[
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Builder(
                            builder: (context) {
                              final isTr =
                                  AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr';
                              return _FilterChip(
                                label: '🌐 ${AppLocalizations.of(context)?.get('lang_all') ?? (isTr ? 'Tümü' : 'All')}',
                                selected: activeLang == null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(swipeProvider.notifier)
                                      .updateFilters(
                                        languageFilter: null,
                                        providerFilter: activeProv,
                                      );
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                          ..._getLanguages(context).entries.map((entry) {
                            return _FilterChip(
                              label: _getLanguageLabel(context, entry.key),
                              selected: activeLang == entry.key,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: entry.key,
                                      providerFilter: activeProv,
                                    );
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              final isTr =
                                  AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr';
                              return Text(
                                isTr
                                    ? 'DİJİTAL YAYIN PLATFORMU'
                                    : 'STREAMING PLATFORMS',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                          if (activeProv != null) ...[
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Builder(
                            builder: (context) {
                              final isTr =
                                  AppLocalizations.of(
                                    context,
                                  )?.locale.languageCode ==
                                  'tr';
                              return _FilterChip(
                                label: isTr ? '🎬 Tümü' : '🎬 All',
                                selected: activeProv == null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(swipeProvider.notifier)
                                      .updateFilters(
                                        languageFilter: activeLang,
                                        providerFilter: null,
                                      );
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                          ..._providers.entries.map((entry) {
                            return _FilterChip(
                              label: entry.value,
                              selected: activeProv == entry.key,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: activeLang,
                                      providerFilter: entry.key,
                                    );
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated &&
          next.isAuthenticated) {
        ref.read(socialProvider.notifier).loadFriendSignals();
      }
    });

    final swipeState = ref.watch(swipeProvider);
    final loading = swipeState.loading;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: Stack(
        children: [
          CinematicBackground(
            animate: true,
            child: SafeArea(
              child: loading
                  ? Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.c.gold,
                        ),
                      ),
                    )
                  : _content(swipeState),
            ),
          ),
          if (_showGuide) _buildGestureGuideOverlay(context.c),
        ],
      ),
    );
  }

  Widget _content(SwipeState swipeState) {
    final c = context.c;
    final current = swipeState.current;
    final queue = swipeState.queue;
    final rated = current;

    final statsState = ref.watch(statsProvider);
    final stats = statsState.value ?? {};
    final topGenres = stats['topGenres'] as List<dynamic>? ?? [];
    final likedGenreIds = topGenres.cast<int>().toSet();

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(
                AppLocalizations.of(context)?.get('tab_swipe') ?? 'Rate',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                AppLocalizations.of(context)
                        ?.get('swipe_ratings_count')
                        .replaceAll('{}', rated.toString()) ??
                    '$rated ratings',
                style: TextStyle(color: c.dim, fontSize: 12),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  color:
                      (swipeState.languageFilter != null ||
                          swipeState.providerFilter != null)
                      ? c.red
                      : c.dim,
                ),
                onPressed: () => _showFilterSheet(context, ref, swipeState),
                tooltip:
                    AppLocalizations.of(context)?.locale.languageCode == 'tr'
                    ? 'Filtrele'
                    : 'Filter',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: const EdgeInsets.all(10),
              ),
            ],
          ),
        ),
        // Active Filter Chips
        if (swipeState.languageFilter != null ||
            swipeState.providerFilter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (swipeState.languageFilter != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(
                          _getLanguageLabel(context, swipeState.languageFilter),
                          style: TextStyle(color: c.ink, fontSize: 12),
                        ),
                        backgroundColor: c.card,
                        deleteIconColor: c.dim,
                        onDeleted: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(swipeProvider.notifier)
                              .updateFilters(
                                languageFilter: null,
                                providerFilter: swipeState.providerFilter,
                              );
                        },
                      ),
                    ),
                  if (swipeState.providerFilter != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(
                          _getProviderLabel(context, swipeState.providerFilter),
                          style: TextStyle(color: c.ink, fontSize: 12),
                        ),
                        backgroundColor: c.card,
                        deleteIconColor: c.dim,
                        onDeleted: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(swipeProvider.notifier)
                              .updateFilters(
                                languageFilter: swipeState.languageFilter,
                                providerFilter: null,
                              );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Card Content
        Expanded(
          child: swipeState.error != null && current >= queue.length
              ? _errorView(swipeState.error!)
              : current >= queue.length
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.red.withValues(alpha: 0.1),
                          boxShadow: [
                            BoxShadow(
                              color: c.red.withValues(alpha: 0.15),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.movie_filter_rounded,
                          color: c.red,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Builder(
                        builder: (context) {
                          final isTr =
                              AppLocalizations.of(
                                context,
                              )?.locale.languageCode ==
                              'tr';
                          return Text(
                            isTr ? 'İçerik Kalmadı' : 'No More Content',
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Builder(
                          builder: (context) {
                            final isTr =
                                AppLocalizations.of(
                                  context,
                                )?.locale.languageCode ==
                                'tr';
                            return Text(
                              (swipeState.loadingMore ||
                                      (swipeState.languageFilter == null &&
                                          swipeState.providerFilter == null))
                                  ? (isTr
                                        ? 'Daha fazla yükleniyor...'
                                        : 'Loading more...')
                                  : (isTr
                                        ? 'Filtrenize uygun başka içerik kalmadı.\nFiltreleri temizleyerek devam edebilirsiniz.'
                                        : 'No more content matches your filters.\nYou can clear the filters to continue.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.dim,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: () => _openDetail(queue[current]),
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragX += details.delta.dx;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_dragX > 120) {
                      _rate(3); // Rate Harika (Beğendim)
                    } else if (_dragX < -120) {
                      _rate(0); // Rate Berbat (Beğenmedim)
                    }
                    setState(() {
                      _dragX = 0;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Transform.translate(
                      offset: Offset(_dragX, 0),
                      child: Transform.rotate(
                        angle: _dragX / 1000,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: _SwipeCard(
                            movie: queue[current],
                            dragX: _dragX,
                            likedGenreIds: likedGenreIds,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        // Ratings & Actions
        if (current < queue.length) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double maxWidth = constraints.maxWidth;
                final double scale = maxWidth < 340
                    ? (maxWidth / 340).clamp(0.75, 1.0)
                    : 1.0;

                final double undoSize = 44.0 * scale;
                final double berbatSize = 68.0 * scale;
                final double ehSize = 80.0 * scale;
                final double iyiSize = 80.0 * scale;
                final double harikaSize = 68.0 * scale;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Semantics(
                      label:
                          AppLocalizations.of(context)?.get('semantics_undo') ??
                          'Değerlendirmeyi geri al',
                      button: true,
                      enabled: current > 0,
                      child: SpringButton(
                        onTap: current > 0 ? _undo : null,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: undoSize,
                              height: undoSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.surface,
                              ),
                              child: Icon(
                                Icons.undo_rounded,
                                color: current > 0
                                    ? (c.isLight ? c.dim : Colors.white54)
                                    : (c.isLight
                                          ? c.textFaint
                                          : Colors.white12),
                                size: 20 * scale,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _RatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_berbat') ??
                          'Berbat',
                      color: c.rBerbat,
                      size: berbatSize,
                      onTap: () => _rate(0),
                    ),
                    _RatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_eh') ??
                          'Eh',
                      color: c.rEh,
                      size: ehSize,
                      onTap: () => _rate(1),
                    ),
                    _RatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_iyi') ??
                          'İyi',
                      color: c.rIyi,
                      size: iyiSize,
                      onTap: () => _rate(2),
                    ),
                    _RatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_harika') ??
                          'Harika',
                      color: c.rHarika,
                      size: harikaSize,
                      onTap: () => _rate(3),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SpringButton(
              onTap: () => _rate(-1),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  AppLocalizations.of(context)?.get('onboarding_not_watched') ??
                      'Not Watched',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 180),
      ],
    );
  }

  Widget _errorView(Object error) {
    final c = context.c;
    final isApiKeyMissing = error.toString().contains('TMDB_API_KEY') || error.toString().toLowerCase().contains('tmdb_api_key eksik');
    return Center(
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
                      'Yapılandırma Hatası')
                : (AppLocalizations.of(context)?.get('swipe_failed') ??
                      'Bağlantı kurulamadı'),
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isApiKeyMissing
                  ? (AppLocalizations.of(
                          context,
                        )?.get('browse_api_missing_desc') ??
                        'Sunucu taraflı servis yapılandırma hatası. Lütfen daha sonra tekrar deneyin.')
                  : (AppLocalizations.of(context)?.get('browse_conn_error') ??
                        'İnternet bağlantınızı kontrol edip tekrar deneyin.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(swipeProvider.notifier).loadMore();
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
    );
  }

  Widget _buildGestureGuideOverlay(ThemePalette c) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.red.withValues(alpha: 0.15),
                    border: Border.all(color: c.red.withValues(alpha: 0.3), width: 2),
                  ),
                  child: Icon(Icons.swipe_rounded, color: c.red, size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  isTr ? 'Keşfetme Hareketleri' : 'Discovery Gestures',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isTr
                      ? 'Kartları kaydırarak zevk analizi motorumuzu eğitin!'
                      : 'Swipe cards to train our recommendation engine!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 40),
                _guideRow(
                  Icons.arrow_forward_rounded,
                  c.green,
                  isTr ? 'Sağa Kaydır' : 'Swipe Right',
                  isTr ? 'Beğendim (İyi veya Harika)' : 'Liked (Good or Amazing)',
                ),
                const SizedBox(height: 20),
                _guideRow(
                  Icons.arrow_back_rounded,
                  c.red,
                  isTr ? 'Sola Kaydır' : 'Swipe Left',
                  isTr ? 'Beğenmedim (Eh veya Berbat)' : 'Disliked (Meh or Awful)',
                ),
                const SizedBox(height: 20),
                _guideRow(
                  Icons.touch_app_rounded,
                  c.gold,
                  isTr ? 'Karta Dokun' : 'Tap Card',
                  isTr ? 'Detaylar, Fragman ve Oyuncular' : 'View Details, Trailer & Cast',
                ),
                const SizedBox(height: 50),
                ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await PrefsService.setSwipeGuideShown();
                    if (mounted) {
                      setState(() => _showGuide = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    shadowColor: c.red.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    isTr ? 'Anladım, Keşfetmeye Başla!' : 'Got it, Let\'s Start!',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideRow(IconData icon, Color color, String title, String subtitle) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? c.red : c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? c.red : c.border,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : c.dim,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeCard extends ConsumerWidget {
  final Movie movie;
  final double dragX;
  final Set<int> likedGenreIds;
  const _SwipeCard({
    required this.movie,
    this.dragX = 0.0,
    required this.likedGenreIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final signals = ref.watch(socialProvider).signals;
    final key = "${movie.isTV ? 'tv' : 'movie'}_${movie.id}";
    final friendNames = signals[key] as List<dynamic>?;

    final isRecommended =
        likedGenreIds.isNotEmpty &&
        movie.genreIds.any((id) {
          if (likedGenreIds.contains(id)) return true;
          if (movie.isTV) {
            final mappedMovieId = switch (id) {
              10759 => 28, // Action & Adventure -> Action
              10765 => 878, // Sci-Fi & Fantasy -> Sci-Fi
              10762 => 10751, // Kids -> Family
              _ => id,
            };
            if (likedGenreIds.contains(mappedMovieId)) return true;
          }
          return false;
        });

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                movie.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const PulsingPlaceholder(),
                        errorWidget: (context, url, error) =>
                            const PulsingPlaceholder(),
                      )
                    : const PulsingPlaceholder(),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SpringButton(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MovieDetailSheet.showRecommendSheet(
                        context: context,
                        ref: ref,
                        movie: movie,
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                if (friendNames != null && friendNames.isNotEmpty)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.gold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_alt_rounded,
                            color: c.gold,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            friendNames.length == 1
                                ? (AppLocalizations.of(
                                            context,
                                          )?.locale.languageCode ==
                                          'tr'
                                      ? '${friendNames.first} beğendi'
                                      : 'Liked by ${friendNames.first}')
                                : (AppLocalizations.of(
                                            context,
                                          )?.locale.languageCode ==
                                          'tr'
                                      ? '${friendNames.first} ve ${friendNames.length - 1} arkadaşın beğendi'
                                      : 'Liked by ${friendNames.first} and ${friendNames.length - 1} others'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          movie.isTV
                              ? (AppLocalizations.of(context)?.get('onboarding_tv') ?? 'Dizi')
                              : (AppLocalizations.of(context)?.get('onboarding_movie') ?? 'Film'),
                          style: TextStyle(
                            color: movie.isTV ? c.blue : c.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.gold.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: CinemaShadows.glow(c.gold, strength: 0.35),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.black,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.get('swipe_recommended') ??
                                    'For You',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Swipe indicators overlay
                if (dragX.abs() > 10)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: dragX > 0
                              ? c.rHarika.withValues(
                                  alpha: (dragX / 150).clamp(0.0, 0.5),
                                )
                              : c.rBerbat.withValues(
                                  alpha: (dragX.abs() / 150).clamp(0.0, 0.5),
                                ),
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                if (dragX.abs() > 20)
                  Positioned(
                    top: 24,
                    left: dragX > 0 ? 20 : null,
                    right: dragX < 0 ? 20 : null,
                    child: Transform.rotate(
                      angle: dragX > 0 ? -0.2 : 0.2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: dragX > 0 ? c.rIyi : c.rBerbat,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.black38,
                        ),
                        child: Text(
                          dragX > 0
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('swipe_liked').toUpperCase() ??
                                    'LIKED')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('swipe_disliked').toUpperCase() ??
                                    'DISLIKED'),
                          style: TextStyle(
                            color: dragX > 0 ? c.rHarika : c.rBerbat,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (movie.year.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('(${movie.year})', style: TextStyle(color: c.dim, fontSize: 16)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RatingBtn extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _RatingBtn({
    required this.label,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visualSize = size;
    final touchSize = visualSize < 44.0 ? 44.0 : visualSize;
    final c = context.c;

    return Semantics(
      label: (AppLocalizations.of(context)?.locale.languageCode == 'tr')
          ? '$label olarak değerlendir'
          : 'Rate as $label',
      button: true,
      child: SpringButton(
        onTap: onTap,
        child: SizedBox(
          width: touchSize,
          height: touchSize,
          child: Center(
            child: Container(
              width: visualSize,
              height: visualSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (color == c.rEh || color == c.rHarika || color == c.rIyi)
                      ? Colors.black87
                      : Colors.white,
                  fontSize: visualSize > 72
                      ? 14
                      : 12 * (visualSize / 80.0).clamp(0.85, 1.0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
