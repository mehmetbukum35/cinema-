import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/screens/profile_screen.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';

class MockProfileApiService implements ApiService {
  @override
  void Function()? onSessionExpired;

  @override
  Future<Map<String, dynamic>> getMe() async => {};

  @override
  Future<void> unlinkGoogle({required String password}) async {}

  @override
  Future<void> unlinkApple({required String password}) async {}

  @override
  Future<Map<String, dynamic>> getRecommendations() async => {
    'recommendations': [],
    'unseen': 0,
  };

  @override
  Future<Map<String, dynamic>> getFriends() async => {
    'friends': [],
    'pending_received': [],
    'pending_sent': [],
  };

  @override
  Future<List<dynamic>> getActivityFeed({int? friendId}) async => [];

  @override
  Future<Map<String, dynamic>> getTopProfiles() async => {'profiles': []};

  @override
  Future<Map<String, dynamic>> getSentRecommendations() async => {
    'recommendations': [],
  };

  @override
  Future<Map<String, dynamic>> push(dynamic payload) async => {
    'server_time': DateTime.now().millisecondsSinceEpoch,
  };

  @override
  Future<Map<String, dynamic>> pull(int since) async => {
    'changes': [],
    'server_time': DateTime.now().millisecondsSinceEpoch,
  };

  @override
  Future<void> registerDevice(String token, {String? platform}) async {}

  @override
  Future<void> publishTasteDna(dynamic dna) async {}

  @override
  Future<List<dynamic>> getAllTasteMatches() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setupSecureStorageMock();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_language': 'en'});
  });

  testWidgets('ProfileScreen renders cinema identity section', (tester) async {
    await tester.pumpWidget(pumpApp(const ProfileScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final identity = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          ((w.data?.toUpperCase().contains('CINEMA') ?? false) ||
              (w.data?.toUpperCase().contains('KIMLI') ?? false) ||
              (w.data?.toUpperCase().contains('KİMLİ') ?? false)),
    );
    expect(identity, findsWidgets);
  });

  testWidgets(
    'ProfileScreen displays Google unlink button and Google badge when google_sub is linked',
    (tester) async {
      final mockApi = MockProfileApiService();

      await tester.pumpWidget(
        pumpApp(
          const ProfileScreen(),
          overrides: [
            apiServiceProvider.overrideWithValue(mockApi),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(mockApi, ref);
              notifier.state = AuthState(
                accessToken: 'access_token',
                user: {
                  'id': 1,
                  'email': 'user@google.com',
                  'display_name': 'Google User',
                  'google_sub': 'google_123',
                },
              );
              return notifier;
            }),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Google'), findsOneWidget);

      final scrollFinder = find.byType(CustomScrollView);
      await tester.drag(scrollFinder, const Offset(0, -600));
      await tester.pump();

      final googleUnlinkText = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('Google Bağlantısını Kaldır') ||
                w.data!.contains('Unlink Google Account')),
      );
      expect(googleUnlinkText, findsWidgets);

      expect(find.text('Apple'), findsNothing);
      final appleUnlinkText = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('Apple Bağlantısını Kaldır') ||
                w.data!.contains('Unlink Apple Account')),
      );
      expect(appleUnlinkText, findsNothing);
    },
  );

  testWidgets(
    'ProfileScreen displays Apple unlink button and Apple badge when apple_sub is linked',
    (tester) async {
      final mockApi = MockProfileApiService();

      await tester.pumpWidget(
        pumpApp(
          const ProfileScreen(),
          overrides: [
            apiServiceProvider.overrideWithValue(mockApi),
            authProvider.overrideWith((ref) {
              final notifier = AuthNotifier(mockApi, ref);
              notifier.state = AuthState(
                accessToken: 'access_token',
                user: {
                  'id': 2,
                  'email': 'user@apple.com',
                  'display_name': 'Apple User',
                  'apple_sub': 'apple_456',
                },
              );
              return notifier;
            }),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Apple'), findsOneWidget);

      final scrollFinder = find.byType(CustomScrollView);
      await tester.drag(scrollFinder, const Offset(0, -600));
      await tester.pump();

      final appleUnlinkText = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('Apple Bağlantısını Kaldır') ||
                w.data!.contains('Unlink Apple Account')),
      );
      expect(appleUnlinkText, findsWidgets);

      expect(find.text('Google'), findsNothing);
      final googleUnlinkText = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('Google Bağlantısını Kaldır') ||
                w.data!.contains('Unlink Google Account')),
      );
      expect(googleUnlinkText, findsNothing);
    },
  );
}
