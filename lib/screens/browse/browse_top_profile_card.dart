import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/social.dart';
import '../../providers/social_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../../widgets/pulsing_placeholder.dart';

/// Keşfet'teki yatay "Popüler Listeler" rayının profil kartı: sıra rengi,
/// beğeni kalbi ve poster önizlemeleri. Dokununca web profili açılır.
class BrowseTopProfileCard extends ConsumerWidget {
  final TopProfile profile;
  final int rank;

  const BrowseTopProfileCard({
    super.key,
    required this.profile,
    required this.rank,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    // Ranks 1, 2, 3 have specific colors
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFBC8A5F),
      _ => c.dim,
    };

    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: rank <= 3
            ? Border.all(color: rankColor.withValues(alpha: 0.4), width: 1.5)
            : Border.all(color: c.borderSoft, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final url = Uri.parse(
            ApiService.webProfileUrl(
              profile.username,
              lang: ref.read(localeProvider).languageCode,
            ),
          );
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: rank <= 3 ? 17 : 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: CinemaGradients.crimson,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    profile.shownName.isEmpty
                        ? '?'
                        : profile.shownName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.shownName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        '@${profile.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (profile.isMe)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tr?.get('top_lists_you') ?? 'Sen',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref
                          .read(socialProvider.notifier)
                          .toggleProfileLike(profile);
                    },
                    child: Icon(
                      profile.meLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: profile.meLiked ? c.red : c.dim,
                      size: 18,
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  profile.likeCount.toString(),
                  style: TextStyle(
                    color: profile.meLiked && !profile.isMe ? c.red : c.dim,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                if (profile.isMe) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.favorite_rounded, color: c.dim, size: 12),
                ],
              ],
            ),
            if (profile.previews.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 58,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final pv in profile.previews.take(10)) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: pv.posterUrl.isEmpty
                              ? Container(
                                  width: 38,
                                  height: 58,
                                  color: c.bg,
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: c.dim,
                                    size: 14,
                                  ),
                                )
                              : AppCachedNetworkImage(
                                  imageUrl: pv.posterUrl,
                                  width: 38,
                                  height: 58,
                                  fit: BoxFit.cover,
                                  preset: AppImageCachePreset.avatar,
                                  placeholder: (_, _) => const SizedBox(
                                    width: 38,
                                    height: 58,
                                    child: PulsingPlaceholder(),
                                  ),
                                  errorWidget: (_, _, _) => Container(
                                    width: 38,
                                    height: 58,
                                    color: c.bg,
                                    child: Icon(
                                      Icons.movie_rounded,
                                      color: c.dim,
                                      size: 14,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
