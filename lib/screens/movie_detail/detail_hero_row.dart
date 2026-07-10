import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spring_button.dart';
import 'synergy_badge.dart';

/// Üst şerit: poster (gizle/öner butonlarıyla), başlık, sinerji rozeti,
/// yıl ve tip/süre satırı.
class DetailHeroRow extends StatelessWidget {
  final Movie movie;
  final int runtime;
  final Map<String, dynamic>? communityScore;
  final VoidCallback onBlock;
  final VoidCallback onRecommend;

  const DetailHeroRow({
    super.key,
    required this.movie,
    required this.runtime,
    required this.communityScore,
    required this.onBlock,
    required this.onRecommend,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 100,
                height: 150,
                child: movie.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 180,
                        placeholder: (context, url) =>
                            ColoredBox(color: c.card),
                        errorWidget: (context, url, error) =>
                            ColoredBox(color: c.card),
                      )
                    : ColoredBox(color: c.card),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Tooltip(
                message:
                    AppLocalizations.of(context)?.get('block_and_hide_title') ??
                    'Block and Hide Title',
                child: SpringButton(
                  onTap: onBlock,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.visibility_off_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Tooltip(
                message:
                    AppLocalizations.of(context)?.get('recommend_to_friend') ??
                    'Recommend to Friend',
                child: SpringButton(
                  onTap: onRecommend,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                movie.title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SynergyBadge(movie: movie, communityScore: communityScore),
                ],
              ),
              if (movie.year.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(movie.year, style: TextStyle(color: c.dim, fontSize: 13)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (movie.isTV ? c.blue : c.red).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
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
                  if (runtime > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$runtime ${AppLocalizations.of(context)?.get('detail_minutes') ?? 'dk'}',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
