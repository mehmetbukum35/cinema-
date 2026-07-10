import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spring_button.dart';

/// Aksiyon sırası: izleme listesi anahtarı, paylaş ve (varsa) fragman.
class DetailActionButtons extends StatelessWidget {
  final Movie movie;
  final bool inWatchlist;
  final bool hasTrailer;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onOpenTrailer;

  const DetailActionButtons({
    super.key,
    required this.movie,
    required this.inWatchlist,
    required this.hasTrailer,
    required this.onToggleWatchlist,
    required this.onOpenTrailer,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final watchlistLabel = inWatchlist
        ? (AppLocalizations.of(context)?.get('detail_watchlist_remove') ??
              'Listeden Çıkar')
        : (AppLocalizations.of(context)?.get('detail_watchlist_add') ??
              'İzleme Listesine Ekle');

    return Row(
      children: [
        // Watchlist toggle
        Expanded(
          child: Tooltip(
            message: watchlistLabel,
            child: Semantics(
              button: true,
              label: watchlistLabel,
              child: SpringButton(
                onTap: onToggleWatchlist,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: inWatchlist ? c.red.withValues(alpha: 0.15) : c.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: inWatchlist ? c.red : c.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        inWatchlist
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: inWatchlist ? c.red : c.dim,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        inWatchlist
                            ? (AppLocalizations.of(
                                    context,
                                  )?.get('detail_watchlist_remove') ??
                                  'Listeden Çıkar')
                            : (AppLocalizations.of(
                                    context,
                                  )?.get('detail_watchlist_add_short') ??
                                  'Watchlist'),
                        style: TextStyle(
                          color: inWatchlist ? c.red : c.dim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Share button
        const SizedBox(width: 10),
        Tooltip(
          message: AppLocalizations.of(context)?.get('share') ?? 'Share',
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)?.get('share') ?? 'Share',
            child: SpringButton(
              onTap: () {
                final typeLabel = movie.isTV
                    ? (AppLocalizations.of(context)?.get('onboarding_tv') ??
                          'Dizi')
                    : (AppLocalizations.of(context)?.get('onboarding_movie') ??
                          'Film');
                final shareTemplate =
                    AppLocalizations.of(context)?.get('detail_share_text') ??
                    'What to Watch recommendation: {}';
                final shareText = shareTemplate.replaceAll(
                  '{}',
                  '${movie.title} (${movie.year})\n⭐ ${movie.voteAverage.toStringAsFixed(1)} · $typeLabel',
                );
                Share.share(shareText);
              },
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Icon(Icons.share_rounded, color: c.dim, size: 18),
              ),
            ),
          ),
        ),
        // Trailer button (only shown when available)
        if (hasTrailer) ...[
          const SizedBox(width: 10),
          Tooltip(
            message:
                AppLocalizations.of(context)?.get('detail_trailer') ??
                'Trailer',
            child: Semantics(
              button: true,
              label:
                  AppLocalizations.of(context)?.get('detail_trailer') ??
                  'Trailer',
              child: SpringButton(
                onTap: onOpenTrailer,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_circle_rounded,
                        color: Color(0xFFFF0000),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)?.get('detail_trailer') ??
                            'Trailer',
                        style: const TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
