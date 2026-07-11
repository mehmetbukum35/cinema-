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

  final client = MockClient((request) async {
    if (request.url.path.endsWith('/3/movie/popular') ||
        request.url.path.endsWith('/3/discover/movie')) {
      return http.Response(jsonEncode(mockMovies), 200);
    } else if (request.url.path.endsWith('/3/tv/popular') ||
        request.url.path.endsWith('/3/discover/tv')) {
      return http.Response(jsonEncode(mockTv), 200);
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

        // 1. Start App with overridden ApiService & TmdbService
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiServiceProvider.overrideWithValue(mockApi),
              tmdbServiceProvider.overrideWithValue(mockTmdb),
            ],
            child: const NeIzlesemApp(showOnboarding: false),
          ),
        );

        // Settle initial async updates
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pump(const Duration(milliseconds: 480));
        await tester.pumpAndSettle();

        // Verify we are on the Browse screen initially
        expect(find.text('Browse'), findsOneWidget);

        // 2. Navigate to Profile Screen
        final profileTabFinder = find.text('Profile');
        expect(profileTabFinder, findsOneWidget);
        await tester.tap(profileTabFinder);
        await tester.pumpAndSettle();

        // Verify we are on Profile and see Cloud Sync section
        expect(find.text('Cloud Sync'), findsOneWidget);

        // 3. Click "Sign In" button to open AuthSheet
        final signInBtnFinder = find.text('Sign In');
        expect(signInBtnFinder, findsOneWidget);
        await tester.tap(signInBtnFinder);
        await tester.pumpAndSettle();

        // Verify the AuthSheet/Modal is displayed
        expect(find.text('Sign in to continue'), findsOneWidget);

        // 4. Fill in Email and Password fields
        final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
        final passwordFieldFinder = find.byKey(
          const ValueKey('auth_password_field'),
        );
        expect(emailFieldFinder, findsOneWidget);
        expect(passwordFieldFinder, findsOneWidget);

        await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
        await tester.enterText(passwordFieldFinder, 'password123');
        await tester.pump();

        // 5. Submit Form / Click Login Button
        final loginBtnFinder = find.byType(ElevatedButton);
        await tester.tap(loginBtnFinder);
        await tester.pumpAndSettle();

        // Verify login api was successfully called
        expect(mockApi.loginCalled, isTrue);

        // Verify we are logged in (displays display_name "Integration User" and logout icon)
        expect(find.text('Integration User'), findsOneWidget);
        expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

        // 6. Click "Sync Now" button to execute Sync flow
        final syncNowBtnFinder = find.text('Sync Now');
        expect(syncNowBtnFinder, findsOneWidget);
        await tester.tap(syncNowBtnFinder);

        // Let sync finish and SnackBar settle
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pumpAndSettle();

        // Verify pull/push sync api was successfully executed
        expect(mockApi.pullCalled, isTrue);
        expect(mockApi.pushCalled, isTrue);

        // Verify last sync time / status is displayed on the cloud sync card
        expect(find.text('Successfully synced'), findsOneWidget);
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

        // Settle onboarding animations and loading
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pumpAndSettle();

        // Verify we are on onboarding (Skip button should be visible)
        final skipBtnFinder = find.text('Skip');
        expect(skipBtnFinder, findsOneWidget);

        await tester.tap(skipBtnFinder);
        await tester.pumpAndSettle();

        // Verify we landed on the Browse screen after skipping
        expect(find.text('Browse'), findsOneWidget);
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

      // 1. Navigate to Rate Tab (tab_swipe is 'Rate')
      final rateTabFinder = find.text('Rate');
      expect(rateTabFinder, findsOneWidget);
      await tester.tap(rateTabFinder);
      await tester.pumpAndSettle();

      // Settle page loading
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      // 2. Verify movie title is visible
      expect(find.text('Swipe Integration Test Movie'), findsOneWidget);

      // 3. Tap on "Amazing" rating button
      final rateBtnFinder = find.text('Amazing');
      expect(rateBtnFinder, findsOneWidget);
      await tester.tap(rateBtnFinder);

      // Settle swipe animations
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // 4. Verify that rating is saved in shared preferences mock database
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

        // 1. Navigate to Profile Screen
        final profileTabFinder = find.text('Profile');
        expect(profileTabFinder, findsOneWidget);
        await tester.tap(profileTabFinder);
        await tester.pumpAndSettle();

        // 2. Click Sign In
        final signInBtnFinder = find.text('Sign In');
        expect(signInBtnFinder, findsOneWidget);
        await tester.tap(signInBtnFinder);
        await tester.pumpAndSettle();

        // 3. Enter credentials and click Login
        final emailFieldFinder = find.byKey(const ValueKey('auth_email_field'));
        final passwordFieldFinder = find.byKey(
          const ValueKey('auth_password_field'),
        );
        await tester.enterText(emailFieldFinder, 'integration@neizlesem.com');
        await tester.enterText(passwordFieldFinder, 'password123');
        await tester.pump();

        final loginBtnFinder = find.byType(ElevatedButton);
        await tester.tap(loginBtnFinder);
        await tester.pumpAndSettle();

        // Verify we are logged in
        expect(find.text('Integration User'), findsOneWidget);

        // 4. Click Logout (find by logout icon)
        final logoutBtnFinder = find.byIcon(Icons.logout_rounded);
        expect(logoutBtnFinder, findsOneWidget);
        await tester.tap(logoutBtnFinder);
        await tester.pumpAndSettle();

        // Verify Logout Confirm Dialog is shown (displays Sign Out button in dialog)
        final confirmBtnFinder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign Out'),
        );
        expect(confirmBtnFinder, findsOneWidget);
        await tester.tap(confirmBtnFinder);
        await tester.pumpAndSettle();

        // Verify we are back in guest mode (Sign In button is visible, Integration User is not)
        expect(find.text('Sign In'), findsOneWidget);
        expect(find.text('Integration User'), findsNothing);
      },
    );
  });
}
