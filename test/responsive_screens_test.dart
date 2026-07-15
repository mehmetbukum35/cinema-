import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/screens/login_screen.dart';
import 'package:ne_izlesem/screens/onboarding_screen.dart';

import 'helpers/widget_test_helpers.dart';
import 'mocks/secure_storage_mock.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  responsiveTestWidgets(
    'Onboarding first step remains responsive',
    (testCase) => pumpApp(
      const OnboardingScreen(),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
    ),
    verify: (tester, testCase) async {
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(OnboardingScreen), findsOneWidget);
    },
  );

  responsiveTestWidgets(
    'Login screen remains responsive',
    (testCase) => pumpApp(
      const LoginScreen(),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
    ),
    verify: (tester, testCase) async {
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );
}
