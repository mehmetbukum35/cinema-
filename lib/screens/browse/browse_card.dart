import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pulsing_placeholder.dart';
import '../../widgets/tonight_pick_card.dart' show recoReasonLabel;
import '../movie_detail_sheet.dart';

/// Keşfet rayı poster kartı: gizle/öner köşe butonları, (opsiyonel) kişisel
/// eşleşme skoru rozeti ve gerekçe satırı.
class BrowseCard extends ConsumerWidget {
  final Movie movie;
  final bool showScore;
  final VoidCallback onTap;
  final VoidCallback onBlocked;

  const BrowseCard({
    super.key,
    required this.movie,
    required this.showScore,
    required this.onTap,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: CinemaShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      movie.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: movie.posterUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 240,
                              placeholder: (context, url) =>
                                  const PulsingPlaceholder(),
                              errorWidget: (context, url, error) =>
                                  const PulsingPlaceholder(),
                            )
                          : const PulsingPlaceholder(),
                      // İnce iç kenar ışığı
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            MovieDetailSheet.confirmBlockMovie(
                              context: context,
                              ref: ref,
                              movie: movie,
                              onBlocked: onBlocked,
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
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
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            MovieDetailSheet.showRecommendSheet(
                              context: context,
                              ref: ref,
                              movie: movie,
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
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
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                      if (showScore)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.66),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    (movie.personalizedMatchScore != null
                                            ? AppColors.green
                                            : AppColors.gold)
                                        .withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  movie.personalizedMatchScore != null
                                      ? Icons.bolt_rounded
                                      : Icons.star_rounded,
                                  color: movie.personalizedMatchScore != null
                                      ? AppColors.green
                                      : AppColors.gold,
                                  size: 11,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  movie.personalizedMatchScore != null
                                      ? '${movie.matchScore}'
                                      : movie.voteAverage.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: movie.personalizedMatchScore != null
                                        ? AppColors.green
                                        : AppColors.gold,
                                    fontSize: 11,
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
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Gerekçe varsa yılın yerine "neden önerildi" satırı — "seni
            // tanıyor" hissini kart seviyesine taşır (yıl detayda zaten var).
            Builder(
              builder: (context) {
                final reason = showScore
                    ? recoReasonLabel(context, movie, compact: true)
                    : null;
                if (reason == null) {
                  return Text(
                    movie.year,
                    style: TextStyle(color: c.dim, fontSize: 12.5),
                  );
                }
                return Row(
                  children: [
                    Icon(
                      movie.recoReasonType == 'friend'
                          ? Icons.favorite_rounded
                          : Icons.auto_awesome_rounded,
                      size: 11,
                      color: c.goldSoft,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.goldSoft,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
