import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/movie.dart';
import '../../../providers/top_list_provider.dart';
import '../../../services/providers.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_cached_image.dart';
import '../../movie_detail_sheet.dart';
import '../../top_list/top_list_edit_screen.dart';
import '../../top_list/top_rank_badge.dart';

/// Profil vitrini: kişisel Top 20 rayı (Film ya da Dizi). Sıra rozetli poster
/// kartları; boşsa "Panteonunu oluştur" CTA'sı. Düzenleme ekranını açar.
class TopListRail extends ConsumerWidget {
  final bool isTV;
  const TopListRail({super.key, required this.isTV});

  void _openEdit(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopListEditScreen(initialTab: isTV ? 1 : 0),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, Movie movie) {
    final service = ref.read(tmdbServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final list = ref.watch(topListProvider(isTV)).value ?? const <Movie>[];
    final label =
        (isTV
            ? tr?.get('top_list_tv_short')
            : tr?.get('top_list_movies_short')) ??
        (isTV ? 'TOP 20 DİZİ' : 'TOP 20 FİLM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ray etiketi: "TOP 20 FİLM · N/20" + Düzenle hapı
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              Flexible(
                child: Text(
                  list.isEmpty
                      ? label
                      : '$label · ${list.length}/${TopListNotifier.cap}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _openEdit(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: c.red.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr?.get('top_list_edit') ?? 'Düzenle',
                        style: TextStyle(
                          color: c.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.tune_rounded, color: c.red, size: 13),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          _emptyCard(context, tr)
        else
          SizedBox(
            height: 225,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              itemBuilder: (ctx, i) => _RankedPosterCard(
                rank: i + 1,
                movie: list[i],
                onTap: () => _openDetail(context, ref, list[i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyCard(BuildContext context, AppLocalizations? tr) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GestureDetector(
        onTap: () => _openEdit(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: c.gold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: c.gold.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: c.gold, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr?.get('top_list_empty_title') ?? 'Panteonunu oluştur',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr?.get('top_list_empty_desc') ?? '',
                      style: TextStyle(color: c.dim, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: c.red, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankedPosterCard extends StatelessWidget {
  final int rank;
  final Movie movie;
  final VoidCallback onTap;

  const _RankedPosterCard({
    required this.rank,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 126,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppCachedNetworkImage(
                      imageUrl: movie.posterUrl,
                      fit: BoxFit.cover,
                      preset: AppImageCachePreset.poster,
                      placeholder: (ctx, url) => ColoredBox(color: c.card),
                      errorWidget: (ctx, url, err) => ColoredBox(color: c.card),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: TopRankBadge(rank: rank, size: 26),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(movie.year, style: TextStyle(color: c.dim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
