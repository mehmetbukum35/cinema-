import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/avatar_initial.dart';
import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../movie_detail/spoiler_comment.dart';
import '../../widgets/spring_button.dart';
import 'open_movie_detail.dart';

/// Arkadaş aktivite kartı: poster, puan rozeti ve (varsa) spoiler korumalı
/// yorum. Dokununca yapım detayı açılır.
class ActivityCard extends ConsumerWidget {
  final ActivityItem act;
  const ActivityCard({super.key, required this.act});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final friendName = act.friendName ?? act.friendUsername;
    final title = act.title;
    final ratingVal = act.rating;
    final posterPath = act.posterPath;
    final isTv = act.isTv;
    final comment = act.comment;
    final isSpoiler = act.isSpoiler;

    Color badgeColor = c.rIyi;
    String badgeText =
        AppLocalizations.of(context)?.get('recap_stat_good') ?? 'Good';
    if (ratingVal == 3) {
      badgeColor = c.rHarika;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_amazing') ?? 'Amazing';
    } else if (ratingVal == 2) {
      badgeColor = c.rIyi;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_good') ?? 'Good';
    } else if (ratingVal == 1) {
      badgeColor = c.rEh;
      badgeText = AppLocalizations.of(context)?.get('recap_stat_meh') ?? 'Meh';
    } else if (ratingVal == 0) {
      badgeColor = c.rBerbat;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_awful') ?? 'Awful';
    }

    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        final movieId = act.movieId;
        if (movieId > 0) {
          openMovieDetailById(context, ref, movieId, isTv);
        }
      },
      child: Semantics(
        button: true,
        label:
            AppLocalizations.of(context)
                ?.get('semantics_activity_item')
                .replaceFirst('{}', friendName)
                .replaceFirst('{}', title) ??
            '$friendName rated $title',
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.borderSoft),
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
                  child: AppCachedNetworkImage(
                    imageUrl: posterPath != null
                        ? 'https://image.tmdb.org/t/p/w200$posterPath'
                        : '',
                    fit: BoxFit.cover,
                    preset: AppImageCachePreset.avatar,
                    errorWidget: (context, url, error) => Container(
                      color: c.border,
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_rounded, color: c.dim),
                    ),
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
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.border,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            avatarInitial(friendName),
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            friendName,
                            style: TextStyle(
                              color: c.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: badgeColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (comment != null && comment.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SpoilerComment(comment: comment, isSpoiler: isSpoiler),
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
