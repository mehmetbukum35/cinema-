import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movie.dart';
import '../../providers/popular_titles_provider.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../../widgets/entrance.dart';
import '../top_list/top_rank_badge.dart';
import 'browse_section_header.dart';

/// Keşfet: topluluk "Popüler Top 20" rayı (film veya dizi).
class BrowsePopularCommunitySection extends ConsumerWidget {
  const BrowsePopularCommunitySection({
    super.key,
    required this.isTV,
    required this.onOpen,
  });

  final bool isTV;
  final void Function(Movie movie) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(popularTitlesProvider(isTV)).value ?? const <PopularTitle>[];
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final title =
        AppLocalizations.of(
          context,
        )?.get(isTV ? 'popular_top_tv_title' : 'popular_top_movies_title') ??
        (isTV ? 'Cinema+ Top 20 Dizi' : 'Cinema+ Top 20 Film');
    final subtitle = AppLocalizations.of(
      context,
    )?.get(isTV ? 'popular_top_tv_subtitle' : 'popular_top_movies_subtitle');
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title: title,
              subtitle: subtitle,
              gradient: CinemaGradients.gold,
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (ctx, i) => _PopularRankCard(
                  entry: items[i],
                  onTap: () => onOpen(items[i].movie),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _PopularRankCard extends StatelessWidget {
  final PopularTitle entry;
  final VoidCallback onTap;

  const _PopularRankCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = entry.movie;
    final votesLabel =
        AppLocalizations.of(
          context,
        )?.get('popular_votes_label').replaceAll('{}', '${entry.votes}') ??
        '${entry.votes}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
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
                      imageUrl: m.posterUrl,
                      fit: BoxFit.cover,
                      preset: AppImageCachePreset.poster,
                      placeholder: (ctx, url) => ColoredBox(color: c.card),
                      errorWidget: (ctx, url, err) => ColoredBox(color: c.card),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: TopRankBadge(rank: entry.rank, size: 28),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Icon(Icons.favorite_rounded, color: c.red, size: 11),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    votesLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
