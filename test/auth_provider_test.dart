import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'mocks/secure_storage_mock.dart';

class MockApiService implements ApiService {
  @override
  void Function()? onSessionExpired;

  Map<String, dynamic> loginResponse = {
    'tokens': {'access_token': 'test_access', 'refresh_token': 'test_refresh'},
    'user': {
      'id': 1,
      'email': 'test@example.com',
      'username': 'testuser',
      'display_name': 'Test User',
      'is_public': 1,
    },
  };

  Map<String, dynamic> registerResponse = {
    'tokens': {'access_token': 'reg_access', 'refresh_token': 'reg_refresh'},
    'user': {
      'id': 2,
      'email': 'reg@example.com',
      'username': 'reguser',
      'display_name': 'Reg User',
      'is_public': 1,
    },
  };

  bool logoutCalled = false;
  bool deleteAccountCalled = false;
  bool changePasswordCalled = false;
  bool forgotPasswordCalled = false;

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return loginResponse;
  }

  @override
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return registerResponse;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    changePasswordCalled = true;
  }

  @override
  Future<void> forgotPassword(String email) async {
    forgotPasswordCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setupSecureStorageMock();

  late MockApiService mockApi;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApi = MockApiService();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(mockApi, ref)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('AuthProvider Tests', () {
    test('login should store tokens and set state as authenticated', () async {
      final notifier = container.read(authProvider.notifier);

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).user, isNull);

      final success = await notifier.login('test@example.com', 'secret123');

      expect(success, isTrue);
      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user, isNotNull);
      expect(state.user!['email'], 'test@example.com');

      expect(await PrefsService.getAccessToken(), 'test_access');
      expect(await PrefsService.getRefreshToken(), 'test_refresh');
    });

    test(
      'register should store tokens and set state as authenticated',
      () async {
        final notifier = container.read(authProvider.notifier);

        final success = await notifier.register(
          'reg@example.com',
          'secret123',
          displayName: 'Reg User',
        );

        expect(success, isTrue);
        final state = container.read(authProvider);
        expect(state.isAuthenticated, isTrue);
        expect(state.user!['email'], 'reg@example.com');
      },
    );

    test('logout should invoke API, clear storage and clear state', () async {
      final notifier = container.read(authProvider.notifier);

      // Authenticate first
      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      // Logout
      await notifier.logout();

      expect(mockApi.logoutCalled, isTrue);
      final state = container.read(authProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);

      expect(await PrefsService.getAccessToken(), isNull);
      expect(await PrefsService.getRefreshToken(), isNull);
    });

    test('deleteAccount should invoke API and clear session', () async {
      final notifier = container.read(authProvider.notifier);

      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      final success = await notifier.deleteAccount();

      expect(success, isTrue);
      expect(mockApi.deleteAccountCalled, isTrue);
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });

    test('changePassword should invoke API', () async {
      final notifier = container.read(authProvider.notifier);

      final success = await notifier.changePassword('old123', 'new123');

      expect(success, isTrue);
      expect(mockApi.changePasswordCalled, isTrue);
    });

    test('forgotPassword should invoke API', () async {
      final notifier = container.read(authProvider.notifier);

      final success = await notifier.forgotPassword('test@example.com');

      expect(success, isTrue);
      expect(mockApi.forgotPasswordCalled, isTrue);
    });
  });
}
