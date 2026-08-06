import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../widgets/app_cached_image.dart';

/// Ortak grid hücresi: poster + alt gradyan + başlık + footer rozeti.
class LibraryPosterCell extends StatelessWidget {
  final Movie movie;
  final Widget? footer;
  final Widget? topLeft;

  const LibraryPosterCell({
    super.key,
    required this.movie,
    this.footer,
    this.topLeft,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppCachedNetworkImage(
            imageUrl: movie.posterUrl,
            fit: BoxFit.cover,
            preset: AppImageCachePreset.poster,
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          if (topLeft != null) Positioned(top: 5, left: 5, child: topLeft!),
          Positioned(
            left: 7,
            right: 7,
            bottom: 7,
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
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 4), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
