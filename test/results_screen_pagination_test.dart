import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/screens/results_screen.dart';

void main() {
  group('discover pagination', () {
    test('continues when the next page contributes a fresh title', () {
      expect(
        shouldContinueDiscoverPagination(batchLength: 20, freshLength: 1),
        isTrue,
      );
    });

    test('stops when TMDB returns an empty page', () {
      expect(
        shouldContinueDiscoverPagination(batchLength: 0, freshLength: 0),
        isFalse,
      );
    });

    test('stops when the whole next page is duplicate content', () {
      expect(
        shouldContinueDiscoverPagination(batchLength: 20, freshLength: 0),
        isFalse,
      );
    });
  });
}
