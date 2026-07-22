import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/screens/search_screen.dart';

void main() {
  group('search request freshness', () {
    test('accepts the active request for the active query', () {
      expect(
        isCurrentSearchRequest(
          requestId: 3,
          currentRequestId: 3,
          query: 'Dune',
          currentQuery: 'Dune',
        ),
        isTrue,
      );
    });

    test('rejects an older failed refresh after a new search starts', () {
      expect(
        isCurrentSearchRequest(
          requestId: 3,
          currentRequestId: 4,
          query: 'Dune',
          currentQuery: 'Arrival',
        ),
        isFalse,
      );
    });

    test('rejects a response whose query is no longer visible', () {
      expect(
        isCurrentSearchRequest(
          requestId: 4,
          currentRequestId: 4,
          query: 'Dune',
          currentQuery: 'Arrival',
        ),
        isFalse,
      );
    });
  });
}
