import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/providers.dart';
import '../services/prefs_service.dart';
import '../services/localization_service.dart';
import '../providers/swipe_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/app_toast.dart';
import 'movie_detail_sheet.dart';
import 'swipe/widgets/dna_milestone_sheet.dart';
import 'swipe/widgets/filter_labels.dart';
import 'swipe/widgets/filter_sheet.dart';
import 'swipe/widgets/gesture_guide_overlay.dart';
import 'swipe/widgets/rating_button_row.dart';
import 'swipe/widgets/swipe_card.dart';
import 'swipe/widgets/swipe_error_view.dart';

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
    var rated = false;
    if (disableAnims) {
      try {
        await notifier.rate(rating);
        rated = true;
      } catch (e) {
        debugPrint("Error rating movie: $e");
        if (mounted) {
          showAppToast(
            context,
            AppLocalizations.of(context)?.get('error_saving_rating') ??
                'Error saving rating.',
            success: false,
          );
        }
      }
      if (rated && mounted) {
        await maybeShowDnaMilestone(context);
      }
      return;
    }
    try {
      await _fadeCtrl.reverse();
      await notifier.rate(rating);
      rated = true;
    } catch (e) {
      debugPrint("Error rating movie: $e");
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context)?.get('error_saving_rating') ??
              'Error saving rating.',
          success: false,
        );
      }
    } finally {
      if (mounted) {
        _fadeCtrl.forward();
      }
    }
    // Eşik anı: 5/25/50. puanlamada DNA'yı çekirdek döngünün içinde
    // keşfettir (bir kez; bkz. PrefsService.pendingDnaMilestone).
    if (rated && mounted) {
      await maybeShowDnaMilestone(context);
    }
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
      try {
        await notifier.undo();
      } catch (e) {
        debugPrint("Error undoing rating: $e");
        if (mounted) {
          showAppToast(
            context,
            AppLocalizations.of(context)?.get('error_undoing_rating') ??
                'Error undoing rating.',
            success: false,
          );
        }
      }
      return;
    }
    try {
      await _fadeCtrl.reverse();
      await notifier.undo();
    } catch (e) {
      debugPrint("Error undoing rating: $e");
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context)?.get('error_undoing_rating') ??
              'Error undoing rating.',
          success: false,
        );
      }
    } finally {
      if (mounted) {
        _fadeCtrl.forward();
      }
    }
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
          if (_showGuide)
            SwipeGestureGuideOverlay(
              palette: context.c,
              onDismiss: () {
                if (mounted) setState(() => _showGuide = false);
              },
            ),
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
                onPressed: () =>
                    SwipeFilterSheet.show(context, ref, swipeState),
                tooltip:
                    AppLocalizations.of(context)?.get('filter') ?? 'Filter',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: const EdgeInsets.all(10),
              ),
            ],
          ),
        ),
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
                          SwipeFilterLabels.languageLabel(
                            context,
                            swipeState.languageFilter,
                          ),
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
                          SwipeFilterLabels.providerLabel(
                            context,
                            swipeState.providerFilter,
                          ),
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
        Expanded(
          child: swipeState.error != null && current >= queue.length
              ? SwipeErrorView(
                  onRetry: () => ref.read(swipeProvider.notifier).loadMore(),
                )
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
                          return Text(
                            AppLocalizations.of(
                                  context,
                                )?.get('no_more_content') ??
                                'No More Content',
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
                            return Text(
                              (swipeState.loadingMore ||
                                      (swipeState.languageFilter == null &&
                                          swipeState.providerFilter == null))
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.get('loading_more') ??
                                        'Loading more...')
                                  : (AppLocalizations.of(context)?.get(
                                          'no_more_content_matches_your_f',
                                        ) ??
                                        'No more content matches your filters.\\nYou can clear the filters to continue.'),
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
                      _rate(2);
                    } else if (_dragX < -120) {
                      _rate(0);
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
                          child: SwipeCard(
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
        if (current < queue.length)
          SwipeRatingButtonRow(
            currentIndex: current,
            onUndo: _undo,
            onRate: _rate,
          )
        else
          const SizedBox(height: 180),
      ],
    );
  }
}
