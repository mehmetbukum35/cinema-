import 'package:flutter/material.dart';
import '../../widgets/app_cached_image.dart';
import '../../models/movie.dart';
import '../../theme/app_theme.dart';

class SimilarCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const SimilarCard({super.key, required this.movie, required this.onTap});

  static const _gold = AppColors.gold;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppCachedNetworkImage(
              imageUrl: movie.posterUrl,
              fit: BoxFit.cover,
              preset: AppImageCachePreset.poster,
              placeholder: (ctx, url) => _placeholder(context),
              errorWidget: (ctx, url, err) => _placeholder(context),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
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
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: _gold, size: 10),
                      const SizedBox(width: 2),
                      Text(
                        movie.voteAverage.toStringAsFixed(1),
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
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

  Widget _placeholder(BuildContext context) => Container(
    color: context.c.card,
    child: Center(
      child: Icon(Icons.movie_rounded, color: context.c.textFaint, size: 24),
    ),
  );
}
