import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/social.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/app_cached_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/spring_button.dart';
import 'social/open_movie_detail.dart';

String _formatReceivedDate(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day.$month.${dt.year}';
}

/// Arkadaşlardan gelen tüm film/dizi önerileri tek listede.
class ReceivedRecommendationsScreen extends ConsumerStatefulWidget {
  const ReceivedRecommendationsScreen({super.key});

  @override
  ConsumerState<ReceivedRecommendationsScreen> createState() =>
      _ReceivedRecommendationsScreenState();
}

class _ReceivedRecommendationsScreenState
    extends ConsumerState<ReceivedRecommendationsScreen> {
  final Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(socialProvider.notifier).loadReceivedRecommendations();
      }
    });
  }

  Future<void> _confirmDelete(ReceivedRecommendationItem item) async {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.card,
        title: Text(
          tr?.get('recommendation_delete') ?? 'Öneriyi sil',
          style: TextStyle(color: c.ink, fontSize: 16),
        ),
        content: Text(
          (tr?.get('recommendation_delete_confirm') ??
                  '“{}” bu listeden kaldırılsın mı?')
              .replaceFirst('{}', item.title),
          style: TextStyle(color: c.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr?.get('profile_cancel') ?? 'İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              tr?.get('delete') ?? 'Sil',
              style: TextStyle(color: c.rBerbat, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(item.id));
    final deleted = await ref
        .read(socialProvider.notifier)
        .deleteRecommendation(item.id);
    if (!mounted) return;
    setState(() => _deletingIds.remove(item.id));
    showAppToast(
      context,
      tr?.get(
            deleted ? 'recommendation_deleted' : 'recommendation_delete_failed',
          ) ??
          (deleted ? 'Öneri silindi.' : 'Öneri silinemedi.'),
      success: deleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final received = ref.watch(socialProvider).receivedRecommendations;

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
                tr?.get('received_recommendations_title') ?? 'Önerilenler',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tr?.get('received_recommendations_subtitle') ??
                    'Sana gelen film ve diziler',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        body: received.isEmpty
            ? _emptyState(c, tr)
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: received.length,
                itemBuilder: (_, i) => _recommendationCard(received[i], c, tr),
              ),
      ),
    );
  }

  Widget _emptyState(ThemePalette c, AppLocalizations? tr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, color: c.dim, size: 42),
          const SizedBox(height: 12),
          Text(
            tr?.get('received_recommendations_empty') ??
                'Henüz sana öneri gelmedi.',
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
    ReceivedRecommendationItem item,
    ThemePalette c,
    AppLocalizations? tr,
  ) {
    final date = _formatReceivedDate(item.createdAt);
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
                child: AppCachedNetworkImage(
                  imageUrl: item.posterPath != null
                      ? 'https://image.tmdb.org/t/p/w200${item.posterPath}'
                      : '',
                  fit: BoxFit.cover,
                  preset: AppImageCachePreset.avatar,
                  errorWidget: (context, url, error) => Container(
                    color: c.border,
                    alignment: Alignment.center,
                    child: Icon(Icons.movie_outlined, color: c.dim, size: 18),
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
                            ?.get('received_recommendation_from')
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
            const SizedBox(width: 4),
            if (_deletingIds.contains(item.id))
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.dim,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: tr?.get('recommendation_delete') ?? 'Öneriyi sil',
                onPressed: () => _confirmDelete(item),
                icon: Icon(Icons.delete_outline_rounded, color: c.rBerbat),
              ),
          ],
        ),
      ),
    );
  }
}
