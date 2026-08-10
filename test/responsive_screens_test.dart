import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/screens/login_screen.dart';
import 'package:ne_izlesem/screens/onboarding_screen.dart';
import 'package:ne_izlesem/services/localization_service.dart';

import 'helpers/widget_test_helpers.dart';
import 'mocks/secure_storage_mock.dart';
import 'support/responsive_test_matrix.dart';

class _LoadingAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  AuthState build() => AuthState(loading: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  testWidgets('Login cannot be popped while authentication is in progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(_LoadingAuthNotifier.new)],
        child: MaterialApp(
          initialRoute: '/login',
          routes: {
            '/': (_) => const Scaffold(body: Text('Home')),
            '/login': (_) => const LoginScreen(),
          },
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
