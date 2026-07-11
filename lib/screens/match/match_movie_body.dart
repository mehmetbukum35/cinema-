import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import 'match_widgets.dart';
import 'similar_card.dart';

/// Film eşleştir modu: arama alanı, sonuç listesi ve benzer içerik ızgarası.
class MatchMovieBody extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final List<Movie> searchResults;
  final bool searching;
  final Movie? selected;
  final List<Movie> similar;
  final bool loadingSimilar;
  final ValueChanged<Movie> onSelectMovie;
  final TmdbService service;
  final ValueChanged<Movie> onSimilarTap;

  const MatchMovieBody({
    super.key,
    required this.searchController,
    required this.onSearch,
    required this.onClear,
    required this.searchResults,
    required this.searching,
    required this.selected,
    required this.similar,
    required this.loadingSimilar,
    required this.onSelectMovie,
    required this.service,
    required this.onSimilarTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        if (selected == null && searchResults.isEmpty && !searching)
          MatchIntroBanner(
            palette: c,
            icon: Icons.movie_filter_rounded,
            title:
                AppLocalizations.of(context)?.get('movie_matcher') ??
                'Movie Matcher',
            description:
                AppLocalizations.of(
                  context,
                )?.get('search_for_a_movie_or_tv_show_') ??
                'Search for a movie or TV show you like, we\'ll analyze its similarities to recommend matching titles.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: c.isLight ? Border.all(color: c.border, width: 1) : null,
            ),
            child: TextField(
              controller: searchController,
              onChanged: onSearch,
              style: TextStyle(color: c.ink, fontSize: 15),
              decoration: InputDecoration(
                hintText:
                    AppLocalizations.of(context)?.get('search_hint') ??
                    'Film veya dizi ara...',
                hintStyle: TextStyle(color: c.dim, fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 20),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: c.dim, size: 18),
                        tooltip:
                            AppLocalizations.of(
                              context,
                            )?.get('semantics_close') ??
                            'Close',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onClear();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (searching) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.c.dim,
          ),
        ),
      );
    }
    if (searchResults.isNotEmpty) return _searchList(context);
    if (selected != null) return _similarGrid(context);
    return _emptyHint(context);
  }

  Widget _emptyHint(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface),
            child: Icon(
              Icons.compare_arrows_rounded,
              color: c.textFaint,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.get('match_search_placeholder') ??
                'Search a movie or TV show',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context)?.get('match_empty_title') ??
                'Find similar titles to what you love instantly',
            style: TextStyle(color: c.dim, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _searchList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: searchResults.length,
      itemBuilder: (ctx, i) {
        final c = ctx.c;
        final m = searchResults[i];
        return GestureDetector(
          onTap: () => onSelectMovie(m),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 44,
                    height: 64,
                    child: m.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: m.posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                ColoredBox(color: c.border),
                            errorWidget: (ctx, url, err) =>
                                ColoredBox(color: c.border),
                          )
                        : ColoredBox(color: c.border),
                  ),
                ),
                const SizedBox(width: 12),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (m.isTV ? c.blue : c.red).withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.isTV
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.get('onboarding_tv') ??
                                        'Dizi')
                                  : (AppLocalizations.of(
                                          context,
                                        )?.get('onboarding_movie') ??
                                        'Film'),
                              style: TextStyle(
                                color: m.isTV ? c.blue : c.red,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (m.year.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              m.year,
                              style: TextStyle(color: c.dim, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.dim, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _similarGrid(BuildContext context) {
    final c = context.c;
    if (loadingSimilar) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.dim),
        ),
      );
    }
    if (similar.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('match_no_similar') ??
              'No similar content found',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Builder(
            builder: (context) {
              final template =
                  AppLocalizations.of(context)?.get('match_similar_to') ??
                  'Similar to "{}"';
              final titleIndex = template.indexOf('{}');
              if (titleIndex == -1) {
                return Text(
                  'Similar to "${selected!.title}"',
                  style: TextStyle(color: c.dim, fontSize: 14),
                );
              }
              final prefix = template.substring(0, titleIndex);
              final suffix = template.substring(titleIndex + 2);
              return RichText(
                text: TextSpan(
                  children: [
                    if (prefix.isNotEmpty)
                      TextSpan(
                        text: prefix,
                        style: TextStyle(color: c.dim, fontSize: 14),
                      ),
                    TextSpan(
                      text: selected!.title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (suffix.isNotEmpty)
                      TextSpan(
                        text: suffix,
                        style: TextStyle(color: c.dim, fontSize: 14),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            itemCount: similar.length,
            itemBuilder: (ctx, i) => SimilarCard(
              movie: similar[i],
              onTap: () => onSimilarTap(similar[i]),
            ),
          ),
        ),
      ],
    );
  }
}
