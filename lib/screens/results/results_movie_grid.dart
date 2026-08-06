import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../theme/app_theme.dart';
import 'movie_card.dart';

class ResultsMovieGrid extends StatelessWidget {
  final ScrollController scrollController;
  final List<Movie> movies;
  final bool loadingMore;
  final void Function(Movie movie) onTap;
  final List<int>? jointGenres;

  const ResultsMovieGrid({
    super.key,
    required this.scrollController,
    required this.movies,
    required this.loadingMore,
    required this.onTap,
    this.jointGenres,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        GridView.builder(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: movies.length,
          itemBuilder: (_, i) => ResultsMovieCard(
            movie: movies[i],
            onTap: () => onTap(movies[i]),
            jointGenres: jointGenres,
          ),
        ),
        if (loadingMore)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.red,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
