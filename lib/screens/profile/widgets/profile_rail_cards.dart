import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/movie.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

/// Ray sonu "showroom" kapısı: kalan öğe sayısı + Tümünü Gör.
/// Vitrin 10 öğede kesildiği için arşivin geri kalanına buradan geçilir.
class SeeAllCard extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;
  const SeeAllCard({super.key, required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 126,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: c.gold.withValues(alpha: 0.06),
                  border: Border.all(
                    color: c.gold.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+$remaining',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)?.get('see_all') ??
                          'Tümünü Gör',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Poster kartlarındaki başlık + yıl satırlarıyla hizalanır.
            const SizedBox(height: 6),
            const Text(' ', style: TextStyle(fontSize: 13.5)),
            const Text(' ', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class WatchlistCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const WatchlistCard({
    super.key,
    required this.movie,
    required this.onTap,
    required this.onRemove,
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
                    movie.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                ColoredBox(color: c.card),
                            errorWidget: (ctx, url, err) =>
                                ColoredBox(color: c.card),
                          )
                        : ColoredBox(color: c.card),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
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

class RatedMovieCard extends StatelessWidget {
  final Movie movie;
  final int rating;
  final bool isPrivate;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const RatedMovieCard({
    super.key,
    required this.movie,
    required this.rating,
    this.isPrivate = false,
    required this.onTap,
    this.onDelete,
  });

  static const _ratingLabels = ['Berbat', 'Eh', 'İyi', 'Harika'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
    final ratingColor = ratingColors[rating.clamp(0, 3)];
    final ratingLabelKey = [
      'profile_berbat',
      'profile_eh',
      'profile_iyi',
      'profile_harika',
    ][rating.clamp(0, 3)];
    final ratingLabel =
        AppLocalizations.of(context)?.get(ratingLabelKey) ??
        _ratingLabels[rating.clamp(0, 3)];

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
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
                    movie.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                ColoredBox(color: c.card),
                            errorWidget: (ctx, url, err) =>
                                ColoredBox(color: c.card),
                          )
                        : ColoredBox(color: c.card),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ratingColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ratingLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (isPrivate)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.65),
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            color: c.gold,
                            size: 14,
                          ),
                        ),
                      ),
                    if (onDelete != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.65),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                          ),
                        ),
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
