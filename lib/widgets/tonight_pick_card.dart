import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/movie.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'pulsing_placeholder.dart';

/// Filmin öneri gerekçesini kullanıcı diline çevirir:
/// seed → "X'i beğendiğin için", friend → "X buna bayıldı". Gerekçe yoksa null.
String? recoReasonLabel(BuildContext context, Movie movie) {
  final reason = movie.recoReason;
  if (reason == null || reason.isEmpty) return null;
  final isFriend = movie.recoReasonType == 'friend';
  final key = isFriend ? 'reco_reason_friend' : 'reco_reason_seed';
  final tpl =
      AppLocalizations.of(context)?.get(key) ??
      (isFriend ? '{x} buna bayıldı' : '{x} beğendiğin için');
  return tpl.replaceFirst('{x}', reason);
}

/// "Bu Gece Ne İzlesem?" vitrin kartı — öneri motorunun en yüksek skorlu
/// seçimini backdrop, uyum yüzdesi ve "neden bu film" gerekçesiyle sunar.
/// Uygulamanın adındaki soruya tek kartla cevap verir.
class TonightPickCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const TonightPickCard({super.key, required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final reason = recoReasonLabel(context, movie);
    final imageUrl = movie.backdropUrl.isNotEmpty
        ? movie.backdropUrl
        : movie.posterUrl;

    return Semantics(
      button: true,
      label:
          '${tr?.get('tonight_title') ?? 'Bu Gece Ne İzlesem?'}: '
          '${movie.title}${reason != null ? '. $reason' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: CinemaShadows.card,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const PulsingPlaceholder(),
                          errorWidget: (context, url, error) =>
                              const PulsingPlaceholder(),
                        )
                      : const PulsingPlaceholder(),
                  // Okunabilirlik için alttan yukarı koyulaşan gradyan.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                        stops: const [0.35, 0.6, 1.0],
                      ),
                    ),
                  ),
                  // İnce iç kenar ışığı (ray kartlarıyla aynı dil).
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.nightlight_round,
                              size: 13,
                              color: c.gold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              (tr?.get('tonight_title') ??
                                      'Bu Gece Ne İzlesem?')
                                  .toUpperCase(),
                              style: TextStyle(
                                color: c.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: c.green.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: c.green.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                '%${movie.matchScore} '
                                '${tr?.get('tonight_match') ?? 'uyum'}',
                                style: TextStyle(
                                  color: c.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (movie.year.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                movie.year,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (reason != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                movie.recoReasonType == 'friend'
                                    ? Icons.favorite_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 13,
                                color: c.goldSoft,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  reason,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
