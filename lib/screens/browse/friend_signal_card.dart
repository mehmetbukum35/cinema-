import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';
import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pulsing_placeholder.dart';
import '../movie_detail_sheet.dart';

/// "Arkadaşlarından Son Sinyaller" rayındaki poster kartı: arkadaşın puan
/// özeti + gizle/öner köşe butonları.
class FriendSignalCard extends ConsumerWidget {
  final ActivityItem item;
  final void Function(Movie) onOpen;
  final void Function(Movie) onBlocked;

  const FriendSignalCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onBlocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final title = item.title;
    final posterPath = item.posterPath ?? '';
    final rating = item.rating;
    final friendName = item.friendName ?? item.friendUsername;

    final ratingKey = rating >= 3
        ? 'browse_rating_excellent'
        : 'browse_rating_good';
    final ratingText =
        AppLocalizations.of(context)?.get(ratingKey) ??
        (rating >= 3 ? 'Harika dedi' : 'İyi dedi');

    final movie = Movie(
      id: item.movieId,
      isTV: item.isTv,
      title: title,
      posterPath: posterPath,
      backdropPath: '',
      overview: '',
      voteAverage: 0,
      releaseDate: '',
      genreIds: const [],
    );

    return GestureDetector(
      onTap: () => onOpen(movie),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: CinemaShadows.card,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        color: c.surface,
                        child: posterPath.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl:
                                    'https://image.tmdb.org/t/p/w342$posterPath',
                                fit: BoxFit.cover,
                                memCacheWidth: 180,
                                placeholder: (context, url) =>
                                    const PulsingPlaceholder(),
                                errorWidget: (context, url, error) =>
                                    const PulsingPlaceholder(),
                              )
                            : const PulsingPlaceholder(),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          MovieDetailSheet.confirmBlockMovie(
                            context: context,
                            ref: ref,
                            movie: movie,
                            onBlocked: () => onBlocked(movie),
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
                    Positioned(
                      top: 4,
                      right: 4,
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
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  rating >= 3
                      ? Icons.favorite_rounded
                      : Icons.thumb_up_rounded,
                  color: c.red,
                  size: 11,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$friendName $ratingText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
