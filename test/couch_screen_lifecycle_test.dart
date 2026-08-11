import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/providers/couch_provider.dart';
import 'package:ne_izlesem/screens/couch_screen.dart';

import 'helpers/widget_test_helpers.dart';
import 'mocks/couch_api_mock.dart';
import 'mocks/secure_storage_mock.dart';

/// Oturum ekranı 2.5 sn'de bir poll ediyor. Ekran mounted kaldığı sürece bu
/// uygulama arka plandayken de dönüyordu — cepteki telefon saatte ~1.440
/// istek üretiyordu. Arka planda poll durmalı, öne dönünce geri gelmeli.
void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<MockCouchApi> pumpCouchScreen(WidgetTester tester) async {
    final mockApi = MockCouchApi()
      ..activeResponse = sessionJson(status: 'active')
      ..getResponse = sessionJson(status: 'active');

    await tester.pumpWidget(
      pumpApp(
        const CouchScreen(),
        overrides: [
          authProvider.overrideWith(
            () => MockAuthNotifier(
              AuthState(accessToken: 'token', user: {'id': 1}),
            ),
          ),
          couchProvider.overrideWith(() => CouchNotifier(api: mockApi)),
        ],
      ),
    );
    // initState'in postFrame kancası: checkActive + startPolling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return mockApi;
  }

  testWidgets('polling stops while the app is backgrounded', (tester) async {
    final mockApi = await pumpCouchScreen(tester);

    // Önplanda poll dönüyor.
    await tester.pump(const Duration(seconds: 6));
    final whileForeground = mockApi.sessionCalls;
    expect(
      whileForeground,
      greaterThan(0),
      reason: 'ekran açıkken poll çalışmalı',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final atPause = mockApi.sessionCalls;

    await tester.pump(const Duration(seconds: 30));
    expect(
      mockApi.sessionCalls,
      atPause,
      reason: 'arka planda tek bir poll bile gitmemeli',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(
      mockApi.sessionCalls,
      greaterThan(atPause),
      reason: 'öne dönünce poll geri gelmeli',
    );

    // Timer'ı test bitmeden söndür.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  });

  testWidgets('returning to the foreground re-checks the session', (
    tester,
  ) async {
    final mockApi = await pumpCouchScreen(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final atPause = mockApi.activeCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      mockApi.activeCalls,
      greaterThan(atPause),
      reason: 'arka planda kaçırılan durum öne dönünce alınmalı',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  });
}
