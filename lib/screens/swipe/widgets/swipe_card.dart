import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/movie.dart';
import '../../../providers/social_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/pulsing_placeholder.dart';
import '../../../widgets/spring_button.dart';
import '../../../widgets/tonight_pick_card.dart' show recoReasonLabel;
import '../../movie_detail_sheet.dart';

/// Swipe kuyruğundaki film/dizi kartı ve sürükleme göstergeleri.
class SwipeCard extends ConsumerWidget {
  final Movie movie;
  final double dragX;
  final Set<int> likedGenreIds;

  const SwipeCard({
    super.key,
    required this.movie,
    this.dragX = 0.0,
    required this.likedGenreIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final signals = ref.watch(socialProvider).signals;
    final friendNames = signals.friendsFor(movieId: movie.id, isTv: movie.isTV);

    final reason = recoReasonLabel(context, movie);
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
                        memCacheWidth: 500,
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
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_tv') ??
                                    'Dizi')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_movie') ??
                                    'Film'),
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
                            boxShadow: CinemaShadows.glow(
                              c.gold,
                              strength: 0.35,
                            ),
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
                if (dragX.abs() > 10)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: dragX > 0
                              ? c.rIyi.withValues(
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
                            color: dragX > 0 ? c.rIyi : c.rBerbat,
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
        if (reason != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                movie.recoReasonType == 'friend'
                    ? Icons.favorite_rounded
                    : Icons.auto_awesome_rounded,
                size: 12,
                color: c.goldSoft,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.goldSoft,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ] else if (movie.year.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('(${movie.year})', style: TextStyle(color: c.dim, fontSize: 16)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
