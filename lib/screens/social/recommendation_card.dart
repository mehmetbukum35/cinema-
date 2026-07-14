import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pulsing_placeholder.dart';
import '../../widgets/spring_button.dart';
import 'open_movie_detail.dart';

/// Gelen tek bir öneri kartı (gönderen + yapım + varsa not).
class RecommendationInboxCard extends ConsumerWidget {
  final RecommendationInboxItem rec;
  final bool isLast;
  const RecommendationInboxCard({
    super.key,
    required this.rec,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final fromName = rec.fromName ?? rec.fromUsername;
    final title = rec.title;
    final note = rec.note ?? '';
    final posterPath = rec.posterPath;
    final isTv = rec.isTv;
    final seen = rec.seen;

    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        final movieId = rec.movieId;
        if (movieId > 0) {
          openMovieDetailById(context, ref, movieId, isTv);
        }
      },
      child: Semantics(
        button: true,
        label:
            AppLocalizations.of(context)
                ?.get('semantics_recommendation_item')
                .replaceFirst('{}', fromName)
                .replaceFirst('{}', title) ??
            'Recommendation from $fromName: $title',
        child: Container(
          margin: EdgeInsets.only(bottom: isLast ? 24 : 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: seen ? c.borderSoft : c.gold.withValues(alpha: 0.5),
            ),
            boxShadow: CinemaShadows.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 60,
                  height: 90,
                  child: posterPath != null
                      ? CachedNetworkImage(
                          imageUrl:
                              'https://image.tmdb.org/t/p/w200$posterPath',
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const PulsingPlaceholder(),
                          errorWidget: (context, url, error) => Container(
                            color: c.border,
                            alignment: Alignment.center,
                            child: Icon(Icons.movie_rounded, color: c.dim),
                          ),
                        )
                      : Container(
                          color: c.border,
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_rounded, color: c.dim),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.card_giftcard_rounded,
                          color: c.gold,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)
                                    ?.get('recommended_by_user')
                                    .replaceAll('{}', fromName) ??
                                'Recommended by $fromName',
                            style: TextStyle(
                              color: c.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTv
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_tv') ??
                                'TV Show')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_movie') ??
                                'Movie'),
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '"$note"',
                        style: TextStyle(
                          color: c.dim,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
