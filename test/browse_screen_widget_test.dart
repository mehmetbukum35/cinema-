import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/screens/browse_screen.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/widgets/shimmer.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BrowseScreen shows skeleton while loading', (tester) async {
    await tester.pumpWidget(
      pumpApp(
        const BrowseScreen(),
        overrides: [tmdbServiceProvider.overrideWithValue(emptyTmdbService())],
      ),
    );
    await tester.pump();

    expect(find.byType(Shimmer), findsWidgets);
  });
}
