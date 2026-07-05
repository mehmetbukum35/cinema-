import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../providers/watchlist_provider.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/pulsing_placeholder.dart';
import '../widgets/entrance.dart';
import 'movie_detail_sheet.dart';

class WatchlistScreen extends ConsumerWidget {
  final bool isActive;
  const WatchlistScreen({super.key, this.isActive = true});

  void _openDetail(BuildContext context, WidgetRef ref, Movie movie) {
    HapticFeedback.lightImpact();
    final service = ref.read(tmdbServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final watchlistState = ref.watch(watchlistProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
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
                AppLocalizations.of(context)?.get('profile_watchlist') ?? '',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            watchlistState.maybeWhen(
              data: (list) => Text(
                '${list.length} ${AppLocalizations.of(context)?.get('watchlist_items') ?? ''}',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      body: CinematicBackground(
        animate: isActive,
        child: watchlistState.when(
          loading: _loadingSkeleton,
          error: (err, st) => _errorScreen(context, ref),
          data: (watchlist) => watchlist.isEmpty
              ? _empty(context)
              : _grid(context, ref, watchlist),
        ),
      ),
    );
  }

  Widget _loadingSkeleton() => GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.64,
    ),
    itemCount: 6,
    itemBuilder: (ctx, i) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: const PulsingPlaceholder(),
    ),
  );

  Widget _errorScreen(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: c.red, size: 48),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.locale.languageCode == 'tr'
                ? 'Yüklenirken bir hata oluştu.'
                : 'An error occurred while loading.',
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

  Widget _empty(BuildContext context) {
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
            child: Icon(Icons.bookmark_border_rounded, color: c.dim, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.get('watchlist_empty_title') ?? '',
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.get('watchlist_empty_desc') ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<Movie> watchlist) {
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.64,
      ),
      itemCount: watchlist.length,
      itemBuilder: (ctx, i) {
        final m = watchlist[i];
        return GestureDetector(
          onTap: () => _openDetail(context, ref, m),
          onLongPress: () => _confirmRemove(context, ref, m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                m.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: m.posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => const PulsingPlaceholder(),
                        errorWidget: (ctx, url, err) =>
                            const PulsingPlaceholder(),
                      )
                    : const PulsingPlaceholder(),
                 Positioned(
                  top: 6,
                  left: 6,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      MovieDetailSheet.confirmBlockMovie(
                        context: context,
                        ref: ref,
                        movie: m,
                        onBlocked: () {},
                      );
                    },
                    child: Container(
                      width: 24,
                      height: 24,
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
                        Icons.visibility_off_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.5, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
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
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star_rounded, color: c.gold, size: 13.5),
                          const SizedBox(width: 2),
                          Text(
                            m.voteAverage.toStringAsFixed(1),
                            style: TextStyle(
                              color: c.gold,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            m.isTV
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_tv') ??
                                      '')
                                : (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_movie') ??
                                      ''),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => _confirmRemove(context, ref, m),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
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

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Movie m,
  ) async {
    final c = context.c;
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    final messenger = ScaffoldMessenger.of(context);
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
          AppLocalizations.of(context)?.locale.languageCode == 'tr'
              ? 'Listeden çıkarılsın mı?'
              : 'Remove from watchlist?',
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
              AppLocalizations.of(context)?.locale.languageCode == 'tr'
                  ? 'Çıkar'
                  : 'Remove',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(watchlistProvider.notifier).remove(m.id, m.isTV);
      if (!context.mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isTr
                ? '${m.title} izleme listesinden çıkarıldı.'
                : '${m.title} removed from watchlist.',
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: isTr ? 'Geri Al' : 'Undo',
            textColor: c.red,
            onPressed: () async {
              await ref.read(watchlistProvider.notifier).add(m);
            },
          ),
        ),
      );
    }
  }
}
