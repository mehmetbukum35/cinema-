import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pulsing_placeholder.dart';
import 'library_poster_cell.dart';

const libraryGridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
  childAspectRatio: 0.62,
);

class LibraryLoadingSkeleton extends StatelessWidget {
  const LibraryLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: libraryGridDelegate,
      itemCount: 9,
      itemBuilder: (ctx, i) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: const PulsingPlaceholder(),
      ),
    );
  }
}

class LibraryWatchlistGrid extends StatelessWidget {
  final List<Movie> items;
  final ValueChanged<Movie> onOpen;
  final ValueChanged<Movie> onLongPressRemove;
  final Future<void> Function() onRefresh;

  const LibraryWatchlistGrid({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onLongPressRemove,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: onRefresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: libraryGridDelegate,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final m = items[i];
          return GestureDetector(
            onTap: () => onOpen(m),
            onLongPress: () => onLongPressRemove(m),
            child: LibraryPosterCell(
              movie: m,
              footer: Row(
                children: [
                  Icon(Icons.star_rounded, color: c.gold, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    m.voteAverage.toStringAsFixed(1),
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class LibraryRatedGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<Movie> onOpen;
  final ValueChanged<Movie> onLongPressDelete;
  final Future<void> Function() onRefresh;

  const LibraryRatedGrid({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onLongPressDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: onRefresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: libraryGridDelegate,
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final m = item['movie'] as Movie;
          final rating = (item['rating'] as int).clamp(0, 3);
          final isPrivate = (item['is_private'] as int? ?? 0) == 1;
          final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
          final ratingLabelKey = [
            'profile_berbat',
            'profile_eh',
            'profile_iyi',
            'profile_harika',
          ][rating];
          final ratingLabel =
              AppLocalizations.of(context)?.get(ratingLabelKey) ??
              const ['Awful', 'Meh', 'Good', 'Amazing'][rating];

          return GestureDetector(
            onTap: () => onOpen(m),
            onLongPress: () => onLongPressDelete(m),
            child: LibraryPosterCell(
              movie: m,
              topLeft: isPrivate
                  ? Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      child: Icon(Icons.lock_rounded, color: c.gold, size: 12),
                    )
                  : null,
              footer: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ratingColors[rating].withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ratingLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
