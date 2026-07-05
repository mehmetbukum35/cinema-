import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/prefs_service.dart';

void main() {
  group('Cosine Similarity & Recommendation Math Tests', () {
    test(
      'calculateSimilarity should return 0.0 when user vector is empty (Cold Start Guard)',
      () {
        final userVector = <int, double>{};
        final movieGenres = [28, 12]; // Action, Adventure
        final similarity = PrefsService.calculateSimilarity(
          userVector,
          movieGenres,
        );
        expect(similarity, equals(0.0));
      },
    );

    test(
      'calculateSimilarity should return 0.0 when movie genres list is empty',
      () {
        final userVector = {28: 3.0, 12: 2.0};
        final movieGenres = <int>[];
        final similarity = PrefsService.calculateSimilarity(
          userVector,
          movieGenres,
        );
        expect(similarity, equals(0.0));
      },
    );

    test(
      'calculateSimilarity should calculate perfect matching (1.0) when single genre aligns',
      () {
        final userVector = {28: 2.0}; // Action only
        final movieGenres = [28]; // Action movie
        final similarity = PrefsService.calculateSimilarity(
          userVector,
          movieGenres,
        );
        // Dot product: 2.0 * 1 = 2.0
        // User norm: sqrt(2^2) = 2.0
        // Movie norm: sqrt(1^2) = 1.0
        // Similarity = 2.0 / (2.0 * 1.0) = 1.0
        expect(similarity, closeTo(1.0, 0.0001));
      },
    );

    test(
      'calculateSimilarity should return positive value for partial alignment',
      () {
        final userVector = {28: 3.0, 12: 1.0}; // Action and Adventure weights
        final movieGenres = [28, 35]; // Action and Comedy movie
        final similarity = PrefsService.calculateSimilarity(
          userVector,
          movieGenres,
        );
        // Dot product: 3.0 * 1 (for 28) + 0 (for 35) = 3.0
        // User norm: sqrt(3^2 + 1^2) = sqrt(10) = 3.16227
        // Movie norm: sqrt(1^2 + 1^2) = sqrt(2) = 1.41421
        // Expected = 3.0 / (3.16227 * 1.41421) = 3.0 / 4.47213 = 0.6708
        expect(similarity, closeTo(0.6708, 0.001));
      },
    );

    test(
      'calculateSimilarity should penalize matching when user vector contains negative weights',
      () {
        final userVector = {
          28: 3.0, // Action: liked
          27: -2.0, // Horror: hated (Berbat rating penalty)
        };

        // Case A: Action + Adventure movie (no Horror)
        final movieA = [28, 12];
        final simA = PrefsService.calculateSimilarity(userVector, movieA);
        // Dot product: 3.0
        // Norm user: sqrt(3^2 + (-2)^2) = sqrt(13) = 3.605
        // Norm movie: sqrt(2) = 1.414
        // Expected = 3.0 / 5.099 = 0.588

        // Case B: Action + Horror movie (contains Horror)
        final movieB = [28, 27];
        final simB = PrefsService.calculateSimilarity(userVector, movieB);
        // Dot product: 3.0 * 1 + (-2.0) * 1 = 1.0
        // Norm user: sqrt(13) = 3.605
        // Norm movie: sqrt(2) = 1.414
        // Expected = 1.0 / 5.099 = 0.196

        expect(simA, greaterThan(simB));
        expect(simB, closeTo(0.196, 0.001));
      },
    );

    test(
      'mixed preferences should yield lower score than pure liked matches',
      () {
        final pureLiked = PrefsService.calculateSimilarity({28: 5.0}, [28]);
        final mixed = PrefsService.calculateSimilarity(
          {28: 5.0, 27: -2.0},
          [28, 27],
        );
        expect(mixed, lessThan(pureLiked));
      },
    );

    test('purely disliked genres should yield negative similarity score', () {
      final similarity = PrefsService.calculateSimilarity({27: -2.0}, [27]);
      expect(similarity, lessThan(0.0));
      expect(similarity, closeTo(-1.0, 0.0001));
    });
  });
}
