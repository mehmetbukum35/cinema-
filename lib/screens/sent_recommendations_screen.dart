import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/social.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/pulsing_placeholder.dart';
import '../widgets/spring_button.dart';
import 'social/open_movie_detail.dart';

String _formatSentDate(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day.$month.${dt.year}';
}

/// Arkadaşlara gönderilen tüm film/dizi önerileri tek listede.
class SentRecommendationsScreen extends ConsumerStatefulWidget {
  const SentRecommendationsScreen({super.key});

  @override
  ConsumerState<SentRecommendationsScreen> createState() =>
      _SentRecommendationsScreenState();
}

class _SentRecommendationsScreenState
    extends ConsumerState<SentRecommendationsScreen> {
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
    final sent = ref.watch(socialProvider).sentRecommendations;

    return CinematicBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: c.ink,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: tr?.get('semantics_go_back') ?? 'Back',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr?.get('sent_recommendations_title') ?? 'Önerdiklerim',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tr?.get('sent_recommendations_subtitle') ??
                    'Arkadaşlarına gönderdiklerin',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        body: sent.isEmpty
            ? _emptyState(c, tr)
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: sent.length,
                itemBuilder: (_, i) => _recommendationCard(sent[i], c, tr),
              ),
      ),
    );
  }

  Widget _emptyState(ThemePalette c, AppLocalizations? tr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.send_outlined, color: c.dim, size: 42),
          const SizedBox(height: 12),
          Text(
            tr?.get('sent_recommendations_empty') ??
                'Henüz arkadaşlarına öneri göndermedin.',
            style: TextStyle(
              color: c.dim,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationCard(
    SentRecommendationItem item,
    ThemePalette c,
    AppLocalizations? tr,
  ) {
    final date = _formatSentDate(item.createdAt);
    final friend = item.friendLabel;

    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        if (item.movieId > 0) {
          openMovieDetailById(context, ref, item.movieId, item.isTv);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.borderSoft),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 42,
                height: 63,
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
                            Icons.movie_outlined,
                            color: c.dim,
                            size: 18,
                          ),
                        ),
                      )
                    : Container(
                        color: c.border,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.movie_outlined,
                          color: c.dim,
                          size: 18,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 4),
                  Text(
                    tr
                            ?.get('sent_recommendation_to')
                            .replaceFirst('{}', friend)
                            .replaceFirst('{}', date) ??
                        '$friend · $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 11.5),
                  ),
                  if (item.note != null && item.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.borderSoft.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.note!,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
