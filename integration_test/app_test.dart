import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/main.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';


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

  Map<String, dynamic> pushResponse = {
    'applied': true,
    'server_time': 6000,
  };

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Integration Tests for Authentication and Sync Flows', () {
    testWidgets(
      'Should start application, navigate to profile, log in, and run cloud sync',
      (WidgetTester tester) async {
        final mockApi = MockIntegrationApiService();

        // 1. Start App with overridden ApiService
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiServiceProvider.overrideWithValue(mockApi),
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
        final passwordFieldFinder = find.byKey(const ValueKey('auth_password_field'));
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

        // Verify we are logged in (displays display_name "Integration User" and logout button)
        expect(find.text('Integration User'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);

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
  });
}
