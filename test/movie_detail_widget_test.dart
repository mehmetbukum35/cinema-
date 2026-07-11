import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/screens/movie_detail_sheet.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MovieDetailSheet renders movie title', (tester) async {
    const title = 'Widget Test Movie';
    final movie = Movie(
      id: 42,
      title: title,
      overview: 'Overview for widget test.',
      voteAverage: 8.1,
      releaseDate: '2024-06-01',
    );
    final service = detailTmdbService(title: title);

    await tester.pumpWidget(
      pumpApp(MovieDetailSheet(movie: movie, service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(title), findsWidgets);
  });
}
