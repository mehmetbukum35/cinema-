import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ne_izlesem/main.dart';
import 'package:ne_izlesem/l10n/en.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/providers/swipe_provider.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

import 'support/app_flow_mocks.dart';
import 'support/app_flow_test_helpers.dart';

Widget wrapAppFlowTest(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: child,
  );
}

Future<void> settleUi(WidgetTester tester, {int steps = 25}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpPastSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2600));
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pump(const Duration(milliseconds: 500));
  await settleUi(tester);
}

Future<void> runLoginAndSyncFlowTest(WidgetTester tester) async {
  final mockApi = MockIntegrationApiService();
  final mockTmdb = createMockTmdbService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        tmdbServiceProvider.overrideWithValue(mockTmdb),
        syncServiceProvider.overrideWith((ref) => AppFlowSyncService(mockApi)),
      ],
      child: wrapAppFlowTest(const NeIzlesemApp(showOnboarding: false)),
    ),
  );

  await pumpPastSplash(tester);

  expect(find.text(kEnStrings['tab_browse']!), findsOneWidget);

  final profileTabFinder = find.text(kEnStrings['tab_profile']!);
  expect(profileTabFinder, findsOneWidget);
  await tester.tap(profileTabFinder);
  await settleUi(tester);

  expect(find.text(kEnStrings['profile_guest']!), findsOneWidget);
  expect(find.text(kEnStrings['profile_not_logged_in']!), findsOneWidget);

  final signInBtnFinder = find.text(kEnStrings['auth_title_login']!);
  expect(signInBtnFinder, findsOneWidget);
  await tester.tap(signInBtnFinder);
  await settleUi(tester);

  expect(find.text(kEnStrings['auth_login_subtitle']!), findsOneWidget);

  final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
  final passwordFieldFinder = find.byKey(const ValueKey('auth_password_field'));
  expect(emailFieldFinder, findsOneWidget);
  expect(passwordFieldFinder, findsOneWidget);

  await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
  await tester.enterText(passwordFieldFinder, 'password123');
  await tester.pump();

  final loginBtnFinder = find.byKey(const ValueKey('auth_login_button'));
  expect(loginBtnFinder, findsOneWidget);
  await tester.tap(loginBtnFinder);
  await settleUi(tester, steps: 30);

  expect(mockApi.loginCalled, isTrue);
  expect(find.text('Integration User'), findsOneWidget);
  expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

  final syncNowBtnFinder = find.text(kEnStrings['sync_now']!);
  expect(syncNowBtnFinder, findsOneWidget);
  await tester.tap(syncNowBtnFinder);
  await settleUi(tester, steps: 30);

  expect(mockApi.pullCalled, isTrue);
  expect(mockApi.pushCalled, isTrue);
  expect(find.text(kEnStrings['sync_success']!), findsOneWidget);
}

Future<void> runOnboardingSkipFlowTest(WidgetTester tester) async {
  final mockApi = MockIntegrationApiService();
  final mockTmdb = createMockTmdbService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        tmdbServiceProvider.overrideWithValue(mockTmdb),
        syncServiceProvider.overrideWith((ref) => AppFlowSyncService(mockApi)),
      ],
      child: wrapAppFlowTest(const NeIzlesemApp(showOnboarding: true)),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2600));
  await settleUi(tester);

  final skipBtnFinder = find.text(kEnStrings['onboarding_skip']!);
  expect(skipBtnFinder, findsOneWidget);

  await tester.tap(skipBtnFinder);
  await settleUi(tester);

  expect(find.text(kEnStrings['tab_browse']!), findsOneWidget);
}

Future<void> runRateTabFlowTest(WidgetTester tester) async {
  final mockApi = MockIntegrationApiService();
  final mockTmdb = createMockTmdbService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        tmdbServiceProvider.overrideWithValue(mockTmdb),
        syncServiceProvider.overrideWith((ref) => AppFlowSyncService(mockApi)),
      ],
      child: wrapAppFlowTest(const NeIzlesemApp(showOnboarding: false)),
    ),
  );

  await pumpPastSplash(tester);

  final rateTabFinder = find.text(kEnStrings['tab_swipe']!);
  expect(rateTabFinder, findsOneWidget);
  await tester.tap(rateTabFinder);
  await settleUi(tester, steps: 30);

  expect(find.text('Swipe Integration Test Movie'), findsOneWidget);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(NeIzlesemApp)),
  );
  await container.read(swipeProvider.notifier).rate(3);
  await settleUi(tester, steps: 15);

  final ratedIds = await PrefsService.getRatedIds();
  expect(ratedIds.contains('movie_1001'), isTrue);
}

Future<void> runLogoutFlowTest(WidgetTester tester) async {
  final mockApi = MockIntegrationApiService();
  final mockTmdb = createMockTmdbService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        tmdbServiceProvider.overrideWithValue(mockTmdb),
        syncServiceProvider.overrideWith((ref) => AppFlowSyncService(mockApi)),
      ],
      child: wrapAppFlowTest(const NeIzlesemApp(showOnboarding: false)),
    ),
  );

  await pumpPastSplash(tester);

  final profileTabFinder = find.text(kEnStrings['tab_profile']!);
  expect(profileTabFinder, findsOneWidget);
  await tester.tap(profileTabFinder);
  await settleUi(tester);

  final signInBtnFinder = find.text(kEnStrings['auth_title_login']!);
  expect(signInBtnFinder, findsOneWidget);
  await tester.tap(signInBtnFinder);
  await settleUi(tester);

  final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
  final passwordFieldFinder = find.byKey(const ValueKey('auth_password_field'));
  await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
  await tester.enterText(passwordFieldFinder, 'password123');
  await tester.pump();

  final loginBtnFinder = find.byKey(const ValueKey('auth_login_button'));
  await tester.tap(loginBtnFinder);
  await settleUi(tester, steps: 30);

  expect(find.text('Integration User'), findsOneWidget);

  final logoutBtnFinder = find.byIcon(Icons.logout_rounded);
  expect(logoutBtnFinder, findsOneWidget);
  await tester.tap(logoutBtnFinder);
  await settleUi(tester);

  final confirmBtnFinder = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, kEnStrings['auth_logout']!),
  );
  expect(confirmBtnFinder, findsOneWidget);
  await tester.tap(confirmBtnFinder);
  await settleUi(tester, steps: 30);

  expect(find.text(kEnStrings['auth_title_login']!), findsOneWidget);
  expect(find.text('Integration User'), findsNothing);
}

void main() {
  setupAppFlowSecureStorageMock();

  setUpAll(initAppFlowTestBinding);

  setUp(setUpAppFlowTestCase);

  tearDown(tearDownAppFlowTestCase);

  group('App flow integration (VM)', () {
    testWidgets(
      'Should start application, navigate to profile, log in, and run cloud sync',
      runLoginAndSyncFlowTest,
    );

    testWidgets(
      'Should start application with onboarding, click skip, and land on Browse screen',
      runOnboardingSkipFlowTest,
    );

    testWidgets(
      'Should navigate to Rate tab and submit a rating',
      runRateTabFlowTest,
    );

    testWidgets(
      'Should start application, log in, and then log out to return to guest mode',
      runLogoutFlowTest,
    );
  });
}
