import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/movie.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../movie_detail_sheet.dart';

/// Arama sonuçları listesi (pull-to-refresh destekli).
class SearchResultsList extends ConsumerWidget {
  final List<Movie> results;
  final Future<void> Function() onRefresh;
  final ValueChanged<Movie> onOpenDetail;
  final void Function(int index) onBlockMovie;

  const SearchResultsList({
    super.key,
    required this.results,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onBlockMovie,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: results.length,
        itemBuilder: (ctx, i) {
          final c = ctx.c;
          final m = results[i];
          final openLabel =
              tr?.get('semantics_search_result').replaceAll('{}', m.title) ??
              'Open ${m.title} details';
          final blockLabel =
              tr?.get('semantics_block_movie').replaceAll('{}', m.title) ??
              'Block and hide ${m.title}';
          return SpringButton(
            onTap: () => onOpenDetail(m),
            child: Semantics(
              button: true,
              label: openLabel,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 58,
                        height: 84,
                        child: m.posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: m.posterUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 120,
                                placeholder: (context, url) =>
                                    ColoredBox(color: c.border),
                                errorWidget: (context, url, error) =>
                                    ColoredBox(color: c.border),
                              )
                            : ColoredBox(color: c.border),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: (m.isTV ? c.blue : c.red).withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  m.isTV
                                      ? (tr?.get('onboarding_tv') ?? 'TV Show')
                                      : (tr?.get('onboarding_movie') ??
                                            'Movie'),
                                  style: TextStyle(
                                    color: m.isTV ? c.blue : c.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (m.year.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  m.year,
                                  style: TextStyle(color: c.dim, fontSize: 13),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Icon(
                                Icons.star_rounded,
                                color: c.gold,
                                size: 13.5,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                m.voteAverage.toStringAsFixed(1),
                                style: TextStyle(
                                  color: c.gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: blockLabel,
                      child: Semantics(
                        button: true,
                        label: blockLabel,
                        child: SpringButton(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            MovieDetailSheet.confirmBlockMovie(
                              context: context,
                              ref: ref,
                              movie: m,
                              onBlocked: () => onBlockMovie(i),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.visibility_off_rounded,
                              color: c.dim,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
