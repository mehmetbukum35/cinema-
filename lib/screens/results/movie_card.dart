import 'dart:math';
import 'package:flutter/material.dart';
import '../../widgets/app_cached_image.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class ResultsMovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final List<int>? jointGenres;

  const ResultsMovieCard({
    super.key,
    required this.movie,
    required this.onTap,
    this.jointGenres,
  });

  int _calculateJointScore(List<int> movieGenreIds, double voteAverage) {
    if (jointGenres == null || jointGenres!.isEmpty) return 0;
    if (movieGenreIds.isEmpty) return 0;
    final common = movieGenreIds.where((id) {
      final mappedId = movie.isTV
          ? (switch (id) {
              10759 => 28,
              10765 => 878,
              10762 => 10751,
              _ => id,
            })
          : id;
      return jointGenres!.contains(mappedId);
    }).length;
    if (common == 0) return 0;
    final double similarity = common / jointGenres!.length;
    final double rawScore = 0.7 * similarity + 0.3 * (voteAverage / 10.0);
    final double z = (rawScore - 0.2) * 4.0;
    final double sigmoid = 1.0 / (1.0 + exp(-z));
    return (40 + (sigmoid * 58)).round().clamp(40, 98);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppCachedNetworkImage(
              imageUrl: movie.posterUrl,
              fit: BoxFit.cover,
              preset: AppImageCachePreset.poster,
              placeholder: (ctx, url) => _placeholder(ctx),
              errorWidget: (ctx, url, err) => _placeholder(ctx),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      (() {
                        final jointScore = _calculateJointScore(
                          movie.genreIds,
                          movie.voteAverage,
                        );
                        if (jointScore > 0) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: c.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: c.green,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '%$jointScore',
                                    style: TextStyle(
                                      color: c.green,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      })(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, color: c.gold, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              movie.voteAverage.toStringAsFixed(1),
                              style: TextStyle(
                                color: c.gold,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: (movie.isTV ? const Color(0xFF1565C0) : c.red)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          movie.isTV
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_tv') ??
                                    'TV')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('onboarding_movie') ??
                                    'Movie'),
                          style: TextStyle(
                            color: movie.isTV ? const Color(0xFF1565C0) : c.red,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.card,
      child: Center(
        child: Icon(Icons.movie_rounded, color: c.border, size: 40),
      ),
    );
  }
}
