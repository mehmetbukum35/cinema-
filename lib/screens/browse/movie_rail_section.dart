import 'package:flutter/material.dart';

import '../../models/movie.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entrance.dart';
import 'browse_card.dart';
import 'browse_section_header.dart';

/// Keşfet: genel yatay film/dizi rayı (başlık + kartlar).
class BrowseMovieRailSection extends StatelessWidget {
  const BrowseMovieRailSection({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    required this.onBlocked,
    this.showScore = false,
    this.badge,
  });

  final String title;
  final List<Movie> items;
  final void Function(Movie movie) onOpen;
  final void Function(Movie movie) onBlocked;
  final bool showScore;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return EntranceFade(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrowseSectionHeader(
            title: title,
            badge: badge,
            gradient: CinemaGradients.gold,
          ),
          SizedBox(
            height: 292,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (ctx, i) => BrowseCard(
                movie: items[i],
                showScore: showScore,
                onTap: () => onOpen(items[i]),
                onBlocked: () => onBlocked(items[i]),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
