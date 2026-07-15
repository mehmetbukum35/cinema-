import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/screens/browse_screen.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/widgets/shimmer.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  responsiveTestWidgets(
    'BrowseScreen loading layout remains responsive',
    (testCase) => pumpApp(
      const BrowseScreen(),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
      overrides: [tmdbServiceProvider.overrideWithValue(emptyTmdbService())],
    ),
    verify: (tester, testCase) async {
      expect(find.byType(Shimmer), findsWidgets);
    },
  );
}
