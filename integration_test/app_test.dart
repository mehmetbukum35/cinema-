import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ne_izlesem/main.dart';
import 'package:ne_izlesem/l10n/en.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/services/prefs_service.dart';

// Mock Secure Storage method handler
void setupSecureStorageMock() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> values = {};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'write':
            final args = methodCall.arguments as Map;
            values[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            final args = methodCall.arguments as Map;
            return values[args['key'] as String];
          case 'delete':
            final args = methodCall.arguments as Map;
            values.remove(args['key'] as String);
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'readAll':
            return values;
          default:
            return null;
        }
      });
}

class MockIntegrationApiService implements ApiService {
  @override
  void Function()? onSessionExpired;

  bool loginCalled = false;
  bool pushCalled = false;
  bool pullCalled = false;

  Map<String, dynamic> loginResponse = {
    'tokens': {'access_token': 'mock_access', 'refresh_token': 'mock_refresh'},
    'user': {
      'id': 100,
      'email': 'integration@neizlesem.com',
      'username': 'integration',
      'display_name': 'Integration User',
      'is_public': 1,
    },
  };

  Map<String, dynamic> pullResponse = {
    'ratings': [],
    'watchlist': [],
    'server_time': 5000,
  };

  Map<String, dynamic> pushResponse = {'applied': true, 'server_time': 6000};

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    loginCalled = true;
    return loginResponse;
  }

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushCalled = true;
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> pull(int since) async {
    pullCalled = true;
    return pullResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TmdbService createMockTmdbService() {
  final mockMovies = {
    'results': [
      {
        'id': 1001,
        'title': 'Swipe Integration Test Movie',
        'overview': 'Incredible integration test overview.',
        'vote_average': 8.7,
        'release_date': '2026-06-23',
        'genre_ids': [28],
        'poster_path': '/mock_poster.jpg',
        'vote_count': 100,
      },
    ],
  };
  final mockTv = {'results': []};
  const emptyProviders = {
    'results': {
      'TR': {'flatrate': [], 'rent': [], 'buy': []},
    },
  };

  final client = MockClient((request) async {
    if (request.url.path.endsWith('/3/movie/popular') ||
        request.url.path.endsWith('/3/discover/movie')) {
      return http.Response(jsonEncode(mockMovies), 200);
    } else if (request.url.path.endsWith('/3/tv/popular') ||
        request.url.path.endsWith('/3/discover/tv')) {
      return http.Response(jsonEncode(mockTv), 200);
    } else if (request.url.path.contains('/watch/providers')) {
      return http.Response(jsonEncode(emptyProviders), 200);
    } else if (request.url.path.contains('/3/')) {
      return http.Response(jsonEncode({'results': []}), 200);
    }
    return http.Response('Not Found', 404);
  });

  return TmdbService(client: client);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_language': 'en'});
  });

  group('Integration Tests for Authentication and Sync Flows', () {
    testWidgets(
      'Should start application, navigate to profile, log in, and run cloud sync',
      (WidgetTester tester) async {
        final mockApi = MockIntegrationApiService();
        final mockTmdb = createMockTmdbService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiServiceProvider.overrideWithValue(mockApi),
              tmdbServiceProvider.overrideWithValue(mockTmdb),
            ],
            child: const NeIzlesemApp(showOnboarding: false),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pump(const Duration(milliseconds: 480));
        await tester.pumpAndSettle();

        expect(find.text(kEnStrings['tab_browse']!), findsOneWidget);

        final profileTabFinder = find.text(kEnStrings['tab_profile']!);
        expect(profileTabFinder, findsOneWidget);
        await tester.tap(profileTabFinder);
        await tester.pumpAndSettle();

        expect(find.text(kEnStrings['profile_guest']!), findsOneWidget);
        expect(find.text(kEnStrings['profile_not_logged_in']!), findsOneWidget);

        final signInBtnFinder = find.text(kEnStrings['auth_title_login']!);
        expect(signInBtnFinder, findsOneWidget);
        await tester.tap(signInBtnFinder);
        await tester.pumpAndSettle();

        expect(find.text(kEnStrings['auth_login_subtitle']!), findsOneWidget);

        final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
        final passwordFieldFinder = find.byKey(
          const ValueKey('auth_password_field'),
        );
        expect(emailFieldFinder, findsOneWidget);
        expect(passwordFieldFinder, findsOneWidget);

        await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
        await tester.enterText(passwordFieldFinder, 'password123');
        await tester.pump();

        final loginBtnFinder = find.byType(FilledButton);
        await tester.tap(loginBtnFinder);
        await tester.pumpAndSettle();

        expect(mockApi.loginCalled, isTrue);
        expect(find.text('Integration User'), findsOneWidget);
        expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

        final syncNowBtnFinder = find.text(kEnStrings['sync_now']!);
        expect(syncNowBtnFinder, findsOneWidget);
        await tester.tap(syncNowBtnFinder);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pumpAndSettle();

        expect(mockApi.pullCalled, isTrue);
        expect(mockApi.pushCalled, isTrue);
        expect(find.text(kEnStrings['sync_success']!), findsOneWidget);
      },
    );

    testWidgets(
      'Should start application with onboarding, click skip, and land on Browse screen',
      (WidgetTester tester) async {
        final mockApi = MockIntegrationApiService();
        final mockTmdb = createMockTmdbService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiServiceProvider.overrideWithValue(mockApi),
              tmdbServiceProvider.overrideWithValue(mockTmdb),
            ],
            child: const NeIzlesemApp(showOnboarding: true),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pumpAndSettle();

        final skipBtnFinder = find.text(kEnStrings['onboarding_skip']!);
        expect(skipBtnFinder, findsOneWidget);

        await tester.tap(skipBtnFinder);
        await tester.pumpAndSettle();

        expect(find.text(kEnStrings['tab_browse']!), findsOneWidget);
      },
    );

    testWidgets('Should navigate to Rate tab and submit a rating', (
      WidgetTester tester,
    ) async {
      final mockApi = MockIntegrationApiService();
      final mockTmdb = createMockTmdbService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(mockApi),
            tmdbServiceProvider.overrideWithValue(mockTmdb),
          ],
          child: const NeIzlesemApp(showOnboarding: false),
        ),
      );

      await tester.pumpAndSettle();

      final rateTabFinder = find.text(kEnStrings['tab_swipe']!);
      expect(rateTabFinder, findsOneWidget);
      await tester.tap(rateTabFinder);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.text('Swipe Integration Test Movie'), findsOneWidget);

      final rateBtnFinder = find.text(kEnStrings['profile_harika']!);
      expect(rateBtnFinder, findsOneWidget);
      await tester.tap(rateBtnFinder);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      final ratedIds = await PrefsService.getRatedIds();
      expect(ratedIds.contains('movie_1001'), isTrue);
    });

    testWidgets(
      'Should start application, log in, and then log out to return to guest mode',
      (WidgetTester tester) async {
        final mockApi = MockIntegrationApiService();
        final mockTmdb = createMockTmdbService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiServiceProvider.overrideWithValue(mockApi),
              tmdbServiceProvider.overrideWithValue(mockTmdb),
            ],
            child: const NeIzlesemApp(showOnboarding: false),
          ),
        );

        await tester.pumpAndSettle();

        final profileTabFinder = find.text(kEnStrings['tab_profile']!);
        expect(profileTabFinder, findsOneWidget);
        await tester.tap(profileTabFinder);
        await tester.pumpAndSettle();

        final signInBtnFinder = find.text(kEnStrings['auth_title_login']!);
        expect(signInBtnFinder, findsOneWidget);
        await tester.tap(signInBtnFinder);
        await tester.pumpAndSettle();

        final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
        final passwordFieldFinder = find.byKey(
          const ValueKey('auth_password_field'),
        );
        await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
        await tester.enterText(passwordFieldFinder, 'password123');
        await tester.pump();

        final loginBtnFinder = find.byType(FilledButton);
        await tester.tap(loginBtnFinder);
        await tester.pumpAndSettle();

        expect(find.text('Integration User'), findsOneWidget);

        final logoutBtnFinder = find.byIcon(Icons.logout_rounded);
        expect(logoutBtnFinder, findsOneWidget);
        await tester.tap(logoutBtnFinder);
        await tester.pumpAndSettle();

        final confirmBtnFinder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(kEnStrings['auth_logout']!),
        );
        expect(confirmBtnFinder, findsOneWidget);
        await tester.tap(confirmBtnFinder);
        await tester.pumpAndSettle();

        expect(find.text(kEnStrings['auth_title_login']!), findsOneWidget);
        expect(find.text('Integration User'), findsNothing);
      },
    );
  });
}
