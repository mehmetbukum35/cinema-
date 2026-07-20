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
import '../../widgets/app_toast.dart';
import '../../widgets/app_cached_image.dart';
import '../../widgets/pulsing_placeholder.dart';

/// Popüler profiller sıralamasındaki tek kart: madalya rengi, beğeni kalbi
/// ve poster önizlemeleri. Dokununca web profili açılır.
class TopProfileCard extends ConsumerWidget {
  final TopProfile profile;
  final int rank;
  const TopProfileCard({super.key, required this.profile, required this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final p = profile;
    // İlk üç sıraya madalya rengi; gerisi sade sıra numarası.
    final rankColor = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFBC8A5F),
      _ => c.dim,
    };

    return Semantics(
      button: true,
      label:
          AppLocalizations.of(context)
              ?.get('semantics_open_public_profile')
              .replaceAll('{}', p.shownName) ??
          'Open ${p.shownName} profile',
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: rank <= 3
              ? Border.all(color: rankColor.withValues(alpha: 0.4))
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final url = Uri.parse(
              ApiService.webProfileUrl(
                p.username,
                lang: ref.read(localeProvider).languageCode,
              ),
            );
            await launchUrl(url, mode: LaunchMode.externalApplication);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          color: rankColor,
                          fontSize: rank <= 3 ? 18 : 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.shownName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '@${p.username}',
                            style: TextStyle(color: c.dim, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (p.isMe)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.get('top_lists_you') ??
                              'You',
                          style: TextStyle(
                            color: c.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    // Kalp + sayı: kendi profilinde yalnızca sayı görünür.
                    if (!p.isMe)
                      Tooltip(
                        message:
                            AppLocalizations.of(context)
                                ?.get(
                                  p.meLiked
                                      ? 'semantics_unlike_profile'
                                      : 'semantics_like_profile',
                                )
                                .replaceAll('{}', p.shownName) ??
                            (p.meLiked
                                ? 'Unlike ${p.shownName} profile'
                                : 'Like ${p.shownName} profile'),
                        child: Semantics(
                          button: true,
                          label:
                              AppLocalizations.of(context)
                                  ?.get(
                                    p.meLiked
                                        ? 'semantics_unlike_profile'
                                        : 'semantics_like_profile',
                                  )
                                  .replaceAll('{}', p.shownName) ??
                              (p.meLiked
                                  ? 'Unlike ${p.shownName} profile'
                                  : 'Like ${p.shownName} profile'),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              p.meLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: p.meLiked ? c.red : c.dim,
                            ),
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final ok = await ref
                                  .read(socialProvider.notifier)
                                  .toggleProfileLike(p);
                              if (!ok && context.mounted) {
                                showAppToast(
                                  context,
                                  AppLocalizations.of(
                                        context,
                                      )?.get('profile_like_failed') ??
                                      'Could not save your like. Please try again.',
                                  success: false,
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    Text(
                      p.likeCount.toString(),
                      style: TextStyle(
                        color: p.meLiked && !p.isMe ? c.red : c.dim,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (p.isMe) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.favorite_rounded, color: c.dim, size: 16),
                    ],
                    const SizedBox(width: 4),
                  ],
                ),
                if (p.previews.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: p.previews.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final pv = p.previews[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: pv.posterUrl.isEmpty
                              ? Container(
                                  width: 62,
                                  color: c.bg,
                                  child: Icon(
                                    Icons.movie_rounded,
                                    color: c.dim,
                                  ),
                                )
                              : AppCachedNetworkImage(
                                  imageUrl: pv.posterUrl,
                                  width: 62,
                                  fit: BoxFit.cover,
                                  preset: AppImageCachePreset.avatar,
                                  placeholder: (_, _) => const SizedBox(
                                    width: 62,
                                    height: 92,
                                    child: PulsingPlaceholder(),
                                  ),
                                  errorWidget: (_, _, _) => Container(
                                    width: 62,
                                    height: 92,
                                    color: c.bg,
                                    child: Icon(
                                      Icons.movie_rounded,
                                      color: c.dim,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
