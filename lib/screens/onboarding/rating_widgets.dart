import 'package:flutter/material.dart';
import '../../widgets/app_cached_image.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class OnboardingMovieCard extends StatelessWidget {
  final Movie movie;
  const OnboardingMovieCard({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppCachedNetworkImage(
                  imageUrl: movie.posterUrl,
                  fit: BoxFit.cover,
                  preset: AppImageCachePreset.poster,
                  placeholder: (context, url) => _placeholder(c),
                  errorWidget: (context, url, error) => _placeholder(c),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      movie.isTV
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_tv') ??
                                '')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('onboarding_movie') ??
                                ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (movie.year.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('(${movie.year})', style: TextStyle(color: c.dim, fontSize: 14)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _placeholder(ThemePalette c) => Container(
    color: c.surface,
    child: const Center(
      child: Icon(Icons.movie_rounded, color: Colors.white24, size: 48),
    ),
  );
}

class OnboardingRatingBtn extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const OnboardingRatingBtn({
    super.key,
    required this.label,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onRatingFill(color),
            fontSize: size > 72 ? 13 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
