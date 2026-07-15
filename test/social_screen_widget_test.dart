import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/screens/social_screen.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  responsiveTestWidgets(
    'SocialScreen tab layout remains responsive',
    (testCase) => pumpApp(
      const SocialScreen(),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
    ),
    verify: (tester, testCase) async {
      await tester.pump(const Duration(milliseconds: 100));
      final isTr = testCase.locale.languageCode == 'tr';
      expect(find.text(isTr ? 'Arkadaşlar' : 'Friends'), findsOneWidget);
      expect(find.text(isTr ? 'İstekler' : 'Requests'), findsOneWidget);
      expect(find.text(isTr ? 'Popüler' : 'Popular'), findsOneWidget);
    },
  );
}
