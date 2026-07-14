import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/social.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/social_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/pulsing_placeholder.dart';
import '../../social/open_movie_detail.dart';

String _formatSentDate(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day.$month.${dt.year}';
}

/// Profilde kullanıcının arkadaşlarına gönderdiği son önerileri listeler.
class SentRecommendationsCard extends ConsumerStatefulWidget {
  const SentRecommendationsCard({super.key});

  @override
  ConsumerState<SentRecommendationsCard> createState() =>
      _SentRecommendationsCardState();
}

class _SentRecommendationsCardState
    extends ConsumerState<SentRecommendationsCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(socialProvider.notifier).loadSentRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const SizedBox.shrink();

    final sent = ref.watch(socialProvider).sentRecommendations;
    if (sent.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.borderSoft),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.send_rounded, color: c.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr?.get('sent_recommendations_title') ??
                      'Recommended to Friends',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.gold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${sent.length}',
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr?.get('sent_recommendations_subtitle') ??
                'Films and shows you shared with friends',
            style: TextStyle(color: c.dim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < sent.take(5).length; i++)
            _SentRecommendationRow(
              item: sent[i],
              isLast: i == sent.take(5).length - 1,
            ),
        ],
      ),
    );
  }
}

class _SentRecommendationRow extends ConsumerWidget {
  final SentRecommendationItem item;
  final bool isLast;

  const _SentRecommendationRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final date = _formatSentDate(item.createdAt);
    final friend = item.friendLabel;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (item.movieId > 0) {
          openMovieDetailById(context, ref, item.movieId, item.isTv);
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.borderSoft),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 42,
                height: 62,
                child: item.posterPath != null
                    ? CachedNetworkImage(
                        imageUrl:
                            'https://image.tmdb.org/t/p/w200${item.posterPath}',
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const PulsingPlaceholder(),
                        errorWidget: (context, url, error) => Container(
                          color: c.border,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.movie_rounded,
                            color: c.dim,
                            size: 18,
                          ),
                        ),
                      )
                    : Container(
                        color: c.border,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.movie_rounded,
                          color: c.dim,
                          size: 18,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tr
                            ?.get('sent_recommendation_to')
                            .replaceFirst('{}', friend)
                            .replaceFirst('{}', date) ??
                        'To $friend · $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
