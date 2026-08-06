import 'package:flutter/material.dart';

import '../../../models/movie.dart';
import '../../../services/localization_service.dart';
import '../../watchlist_screen.dart';
import 'profile_rail_cards.dart';
import 'profile_rail_label.dart';
import 'profile_section_header.dart';

/// Profil kütüphane vitrini: izleme listesi + değerlendirme rayları.
/// Arşivin tamamı [LibraryScreen]'de; burada son 10 öğe + "Tümünü Gör".
class ProfileLibraryRails {
  ProfileLibraryRails._();

  static List<Widget> slivers(
    BuildContext context, {
    required List<Movie> watchlist,
    required List<dynamic> ratedMovies,
    required void Function(Movie movie) onOpenMovie,
    required void Function(Movie movie) onRemoveWatchlist,
    required void Function(Movie movie) onDeleteRated,
  }) {
    if (watchlist.isEmpty && ratedMovies.isEmpty) return [];

    final tr = AppLocalizations.of(context);
    return [
      SliverToBoxAdapter(
        child: ProfileSectionHeader(
          text: tr?.get('library_title') ?? 'Kütüphanen',
        ),
      ),
      if (watchlist.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: ProfileRailLabel(
            label: tr?.get('profile_watchlist') ?? 'İZLEME LİSTESİ',
            count: watchlist.length,
            onSeeAll: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LibraryScreen(initialTab: 0),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 225,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in watchlist.take(10))
                  WatchlistCard(
                    movie: m,
                    onTap: () => onOpenMovie(m),
                    onRemove: () => onRemoveWatchlist(m),
                  ),
                if (watchlist.length > 10)
                  SeeAllCard(
                    remaining: watchlist.length - 10,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LibraryScreen(initialTab: 0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
      if (ratedMovies.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: ProfileRailLabel(
            label: tr?.get('profile_history') ?? 'DEĞERLENDİRDİKLERİM',
            count: ratedMovies.length,
            onSeeAll: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LibraryScreen(initialTab: 1),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 225,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final item
                    in ratedMovies.take(10).cast<Map<String, dynamic>>())
                  RatedMovieCard(
                    movie: item['movie'] as Movie,
                    rating: item['rating'] as int,
                    isPrivate: (item['is_private'] as int? ?? 0) == 1,
                    onTap: () => onOpenMovie(item['movie'] as Movie),
                    onDelete: () => onDeleteRated(item['movie'] as Movie),
                  ),
                if (ratedMovies.length > 10)
                  SeeAllCard(
                    remaining: ratedMovies.length - 10,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LibraryScreen(initialTab: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
      ],
    ];
  }
}
