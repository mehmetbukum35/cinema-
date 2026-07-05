import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/movie.dart';

void main() {
  group('Movie Unit Tests', () {
    test('Movie.fromJson should parse movie JSON correctly', () {
      final json = {
        'id': 123,
        'title': 'Test Movie',
        'poster_path': '/path.jpg',
        'backdrop_path': '/back.jpg',
        'overview': 'This is an overview.',
        'vote_average': 7.8,
        'release_date': '2026-06-23',
        'genre_ids': [28, 12],
      };

      final movie = Movie.fromJson(json, isTV: false);

      expect(movie.id, 123);
      expect(movie.title, 'Test Movie');
      expect(movie.posterPath, '/path.jpg');
      expect(movie.backdropPath, '/back.jpg');
      expect(movie.overview, 'This is an overview.');
      expect(movie.voteAverage, 7.8);
      expect(movie.releaseDate, '2026-06-23');
      expect(movie.isTV, isFalse);
      expect(movie.genreIds, [28, 12]);
      expect(movie.year, '2026');
      expect(movie.matchScore, 78);
      expect(movie.posterUrl, 'https://image.tmdb.org/t/p/w500/path.jpg');
      expect(movie.backdropUrl, 'https://image.tmdb.org/t/p/w780/back.jpg');
    });

    test('Movie.fromJson should parse TV show JSON correctly', () {
      final json = {
        'id': 456,
        'name': 'Test TV Show',
        'poster_path': null,
        'backdrop_path': null,
        'overview': '',
        'vote_average': 8.543,
        'first_air_date': '2025-10-12',
        'genre_ids': [35],
      };

      final movie = Movie.fromJson(json, isTV: true);

      expect(movie.id, 456);
      expect(movie.title, 'Test TV Show');
      expect(movie.posterPath, isNull);
      expect(movie.backdropPath, isNull);
      expect(movie.overview, '');
      expect(movie.voteAverage, 8.543);
      expect(movie.releaseDate, '2025-10-12');
      expect(movie.isTV, isTrue);
      expect(movie.genreIds, [35]);
      expect(movie.year, '2025');
      expect(movie.matchScore, 85);
      expect(movie.posterUrl, '');
      expect(movie.backdropUrl, '');
    });

    test('Movie.fromJson should handle null or missing fields gracefully', () {
      final json = {
        'id': 789,
        // missing title/name, poster, backdrop, overview, vote_average, release_date
      };

      final movie = Movie.fromJson(json, isTV: false);

      expect(movie.id, 789);
      expect(movie.title, '');
      expect(movie.posterPath, isNull);
      expect(movie.overview, '');
      expect(movie.voteAverage, 0.0);
      expect(movie.releaseDate, isNull);
      expect(movie.genreIds, isEmpty);
      expect(movie.year, '');
    });

    test(
      'toStorage and fromStorage should serialize and deserialize correctly',
      () {
        final original = Movie(
          id: 999,
          title: 'Storage Movie',
          posterPath: '/p.jpg',
          backdropPath: '/b.jpg',
          overview: 'Overview',
          voteAverage: 9.0,
          releaseDate: '1999-01-01',
          isTV: true,
          genreIds: [18, 80],
          voteCount: 300,
        );

        final map = original.toStorage();
        final restored = Movie.fromStorage(map);

        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.posterPath, original.posterPath);
        expect(restored.backdropPath, original.backdropPath);
        expect(restored.overview, original.overview);
        expect(restored.voteAverage, original.voteAverage);
        expect(restored.releaseDate, original.releaseDate);
        expect(restored.isTV, original.isTV);
        expect(restored.genreIds, original.genreIds);
        expect(restored.voteCount, original.voteCount);
      },
    );

    test('popularity should parse from JSON and default to 0 when missing', () {
      final withPop = Movie.fromJson({
        'id': 1,
        'title': 'Popular',
        'vote_average': 5.0,
        'popularity': 123.45,
      });
      expect(withPop.popularity, 123.45);

      final withoutPop = Movie.fromJson({'id': 2, 'title': 'No pop'});
      expect(withoutPop.popularity, 0);
    });

    test('popularity and voteCount should survive a storage round-trip', () {
      final original = Movie(
        id: 7,
        title: 'Round Trip',
        overview: '',
        voteAverage: 6.0,
        popularity: 88.8,
        voteCount: 500,
      );
      final restored = Movie.fromStorage(original.toStorage());
      expect(restored.popularity, 88.8);
      expect(restored.voteCount, 500);
    });
  });
}
