import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/providers/social_provider.dart';
import 'package:ne_izlesem/providers/watchlist_provider.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/cultural_preference_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/notification_service.dart';
import 'mocks/secure_storage_mock.dart';

/// ApiException olmayan beklenmeyen bir arıza (soket kopması, serileştirme
/// hatası…). Notifier'ın bunu ham metin olarak arayüze sızdırmadığını doğrular.
class FakeNetworkException implements Exception {
  @override
  String toString() => 'FakeNetworkException: socket closed';
}

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
  bool resendVerificationCalled = false;
  bool unlinkGoogleCalled = false;
  bool unlinkAppleCalled = false;
  bool getMeCalled = false;
  bool resetPasswordCalled = false;
  bool verifyResetCodeCalled = false;
  Completer<Map<String, dynamic>>? getMeGate;

  // Hata enjeksiyonu: ilgili uç çağrıldığında fırlatılır, null ise normal
  // yanıt döner. Sunucunun reddettiği durumlarda notifier'ın oturumu ve yerel
  // veriyi koruduğunu doğrulamak için.
  Exception? loginError;
  Exception? registerError;
  Exception? verifyEmailError;
  Exception? changePasswordError;
  Exception? deleteAccountError;
  Exception? forgotPasswordError;
  Exception? verifyResetCodeError;
  Exception? resetPasswordError;
  Exception? unlinkGoogleError;
  Exception? unlinkAppleError;
  Exception? logoutError;
  Exception? resendVerificationError;
  Exception? getMeError;

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    if (loginError != null) throw loginError!;
    return loginResponse;
  }

  @override
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (registerError != null) throw registerError!;
    return registerResponse;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    if (logoutError != null) throw logoutError!;
  }

  final List<String> revokedRefreshTokens = [];

  @override
  Future<void> revokeRefreshToken(String refreshToken) async {
    revokedRefreshTokens.add(refreshToken);
  }

  @override
  Future<void> deleteAccount(String password) async {
    deleteAccountCalled = true;
    if (deleteAccountError != null) throw deleteAccountError!;
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    changePasswordCalled = true;
    if (changePasswordError != null) throw changePasswordError!;
  }

  @override
  Future<void> forgotPassword(String email) async {
    forgotPasswordCalled = true;
    if (forgotPasswordError != null) throw forgotPasswordError!;
  }

  @override
  Future<void> verifyResetCode(String email, String code) async {
    verifyResetCodeCalled = true;
    if (verifyResetCodeError != null) throw verifyResetCodeError!;
  }

  @override
  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    resetPasswordCalled = true;
    if (resetPasswordError != null) throw resetPasswordError!;
  }

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    if (verifyEmailError != null) throw verifyEmailError!;
    return registerResponse;
  }

  @override
  Future<void> resendVerification(String email) async {
    resendVerificationCalled = true;
    if (resendVerificationError != null) throw resendVerificationError!;
  }

  @override
  Future<void> unlinkGoogle({required String password}) async {
    unlinkGoogleCalled = true;
    if (unlinkGoogleError != null) throw unlinkGoogleError!;
  }

  @override
  Future<void> unlinkApple({required String password}) async {
    unlinkAppleCalled = true;
    if (unlinkAppleError != null) throw unlinkAppleError!;
  }

  @override
  Future<Map<String, dynamic>> getMe() async {
    getMeCalled = true;
    if (getMeError != null) throw getMeError!;
    if (getMeGate != null) return getMeGate!.future;
    return {
      'id': 1,
      'email': 'test@example.com',
      'username': 'testuser',
      'display_name': 'Test User',
      'is_public': 1,
      'google_sub': 'google_123',
      'apple_sub': 'apple_456',
    };
  }

  @override
  Future<Map<String, dynamic>> getRecommendations() async => {
    'recommendations': [],
    'unseen': 0,
  };

  @override
  Future<Map<String, dynamic>> getSentRecommendations() async => {
    'recommendations': [],
  };

  @override
  Future<Map<String, dynamic>> push(dynamic payload) async => {
    'server_time': DateTime.now().millisecondsSinceEpoch,
  };

  @override
  Future<Map<String, dynamic>> pull(
    int since, {
    bool localReset = false,
  }) async => {
    'changes': [],
    'server_time': DateTime.now().millisecondsSinceEpoch,
  };

  @override
  Future<void> registerDevice(String token, {String? platform}) async {}

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
  Future<List<dynamic>> getAllTasteMatches() async => [];

  @override
  Future<void> publishTasteDna(dynamic dna) async {}

  /// SyncService dili buradan okur; ApiService'in gercek alaninin karsiligi.
  @override
  String Function() localeCode = () => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setupSecureStorageMock();

  late MockApiService mockApi;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsService.resetInMemoryCaches();
    // DatabaseHelper testlerde bellek içi sahte listeler kullanır ve singleton
    // olduğu için dosya boyunca yaşar. Temizlenmezse önceki testin bıraktığı
    // puan, sonraki login'i "hesap değişimi" çakışmasına düşürür.
    await DatabaseHelper().hardClearAllData();
    mockApi = MockApiService();
    container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApi),
        authProvider.overrideWith((ref) => AuthNotifier(mockApi, ref)),
      ],
    );
  });

  tearDown(() async {
    NotificationService.instance.debugSetDeleteTokenHandler(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    container.dispose();
  });

  group('AuthProvider Tests', () {
    test('login should store tokens and set state as authenticated', () async {
      final notifier = container.read(authProvider.notifier);

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).user, isNull);

      final result = await notifier.login('test@example.com', 'secret123');

      expect(result.status, AuthStatus.success);
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

        final result = await notifier.register(
          'reg@example.com',
          'secret123',
          displayName: 'Reg User',
        );

        expect(result.status, AuthStatus.success);
        final state = container.read(authProvider);
        expect(state.isAuthenticated, isTrue);
        expect(state.user!['email'], 'reg@example.com');
      },
    );

    test(
      'register with pending_verification should NOT authenticate',
      () async {
        mockApi.registerResponse = {
          'ok': true,
          'pending_verification': true,
          'email': 'reg@example.com',
        };
        final notifier = container.read(authProvider.notifier);

        final result = await notifier.register('reg@example.com', 'secret123');

        expect(result.status, AuthStatus.pendingVerification);
        // Not: secure-storage mock'u testler arasında sıfırlanmadığı için
        // PrefsService yerine yalnızca provider state'i doğrulanır.
        final state = container.read(authProvider);
        expect(state.isAuthenticated, isFalse);
        expect(state.accessToken, isNull);
      },
    );

    test('verifyEmail should complete login with tokens', () async {
      final notifier = container.read(authProvider.notifier);

      final result = await notifier.verifyEmail('reg@example.com', '123456');

      expect(result.status, AuthStatus.success);
      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user!['email'], 'reg@example.com');
      expect(await PrefsService.getAccessToken(), 'reg_access');
    });

    test('resendVerificationCode should invoke API', () async {
      final notifier = container.read(authProvider.notifier);

      final ok = await notifier.resendVerificationCode('reg@example.com');

      expect(ok, isTrue);
      expect(mockApi.resendVerificationCalled, isTrue);
    });

    test('logout should invoke API, clear auth and clear state', () async {
      final notifier = container.read(authProvider.notifier);

      // Authenticate first
      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      // Logout (default: keep local data)
      await notifier.logout();

      expect(mockApi.logoutCalled, isTrue);
      final state = container.read(authProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);

      expect(await PrefsService.getAccessToken(), isNull);
      expect(await PrefsService.getRefreshToken(), isNull);
    });

    test(
      'clearSession should clear auth without requiring logout API',
      () async {
        final notifier = container.read(authProvider.notifier);
        var localTokenInvalidated = false;
        NotificationService.instance.debugSetDeleteTokenHandler(() async {
          localTokenInvalidated = true;
        });

        await notifier.login('test@example.com', 'secret123');
        expect(container.read(authProvider).isAuthenticated, isTrue);

        await notifier.clearSession();

        expect(container.read(authProvider).isAuthenticated, isFalse);
        expect(await PrefsService.getAccessToken(), isNull);
        expect(mockApi.logoutCalled, isFalse);
        expect(localTokenInvalidated, isTrue);
      },
    );

    test('wipeAllData should clear in-memory auth and stored tokens', () async {
      final notifier = container.read(authProvider.notifier);

      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      await notifier.wipeAllData();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(await PrefsService.getAccessToken(), isNull);
    });

    test('changePassword should end session locally', () async {
      final notifier = container.read(authProvider.notifier);

      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      final success = await notifier.changePassword('old123', 'new123');

      expect(success, isTrue);
      expect(mockApi.changePasswordCalled, isTrue);
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });

    test('resetPassword should fully end the local session', () async {
      final notifier = container.read(authProvider.notifier);
      var localTokenInvalidated = false;
      NotificationService.instance.debugSetDeleteTokenHandler(() async {
        localTokenInvalidated = true;
      });
      await notifier.login('test@example.com', 'secret123');
      final oldSocial = container.read(socialProvider.notifier);
      final oldWatchlist = container.read(watchlistProvider.notifier);

      final success = await notifier.resetPassword(
        'test@example.com',
        '123456',
        'new-password-123',
      );

      expect(success, isTrue);
      expect(mockApi.resetPasswordCalled, isTrue);
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(await PrefsService.getAccessToken(), isNull);
      expect(localTokenInvalidated, isTrue);
      expect(container.read(socialProvider.notifier), isNot(same(oldSocial)));
      expect(
        container.read(watchlistProvider.notifier),
        isNot(same(oldWatchlist)),
      );
    });

    test('deleteAccount should invoke API and clear session', () async {
      final notifier = container.read(authProvider.notifier);

      await notifier.login('test@example.com', 'secret123');
      expect(container.read(authProvider).isAuthenticated, isTrue);

      final success = await notifier.deleteAccount('secret123');

      expect(success, isTrue);
      expect(mockApi.deleteAccountCalled, isTrue);
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });

    test('changePassword should invoke API when logged out', () async {
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

    test(
      'should trigger conflict when different user logins and local data exists',
      () async {
        final notifier = container.read(authProvider.notifier);

        // Set last authenticated user id to '1'
        await PrefsService.setLastAuthenticatedUserId('1');
        // Mock ratings data in DatabaseHelper to simulate local data
        await PrefsService.saveRating(
          movieId: 123,
          isTV: false,
          rating: 3,
          metadataLocale: 'tr',
        );

        // Attempt to login as user id '2' (MockApiService register returns id: 2)
        final result = await notifier.register('reg@example.com', 'secret123');

        // Should be conflict
        expect(result.status, AuthStatus.conflict);
        expect(container.read(authProvider).isAuthenticated, isFalse);

        // Complete login with resolution Merge
        await notifier.completeLogin(
          user: result.user!,
          tokens: result.tokens!,
          resolution: ConflictResolution.merge,
        );

        expect(container.read(authProvider).isAuthenticated, isTrue);
        expect(await PrefsService.getLastAuthenticatedUserId(), '2');
        expect(
          await DatabaseHelper().hasAnyLocalData(),
          isTrue,
        ); // rating remains
      },
    );

    test(
      'completeLogin with delete resolution should wipe local data',
      () async {
        final notifier = container.read(authProvider.notifier);

        // Set last authenticated user id to '1'
        await PrefsService.setLastAuthenticatedUserId('1');
        await PrefsService.saveRating(
          movieId: 123,
          isTV: false,
          rating: 3,
          metadataLocale: 'tr',
        );
        await CulturalPreferenceService.save({
          'korean': CulturePreferenceLevel.prefer,
        });

        final result = await notifier.register('reg@example.com', 'secret123');
        expect(result.status, AuthStatus.conflict);

        // Complete login with resolution Delete
        await notifier.completeLogin(
          user: result.user!,
          tokens: result.tokens!,
          resolution: ConflictResolution.delete,
        );

        expect(container.read(authProvider).isAuthenticated, isTrue);
        expect(await PrefsService.getLastAuthenticatedUserId(), '2');
        expect(
          await DatabaseHelper().hasAnyLocalData(),
          isFalse,
        ); // ratings wiped
        expect(
          (await CulturalPreferenceService.load()).isEmpty,
          isTrue,
        ); // culture prefs wiped
      },
    );

    test(
      'completeLogin account switch clears previous user cultural preferences',
      () async {
        final notifier = container.read(authProvider.notifier);

        await PrefsService.setLastAuthenticatedUserId('1');
        // Conflict, hasAnyLocalData gerektirir.
        await PrefsService.saveRating(
          movieId: 55,
          isTV: false,
          rating: 2,
          metadataLocale: 'tr',
        );
        await CulturalPreferenceService.save({
          'turkish': CulturePreferenceLevel.prefer,
        }, source: 'explicit_edit');

        final result = await notifier.register('reg2@example.com', 'secret123');
        expect(result.status, AuthStatus.conflict);

        await notifier.completeLogin(
          user: result.user!,
          tokens: result.tokens!,
          resolution: ConflictResolution.merge,
        );

        expect(await PrefsService.getLastAuthenticatedUserId(), '2');
        expect((await CulturalPreferenceService.load()).isEmpty, isTrue);
      },
    );

    test(
      'should trigger conflict when guest registers and local data exists',
      () async {
        final notifier = container.read(authProvider.notifier);

        // Set last authenticated user id to null (guest mode)
        await PrefsService.setLastAuthenticatedUserId(null);
        await PrefsService.saveRating(
          movieId: 123,
          isTV: false,
          rating: 3,
          metadataLocale: 'tr',
        );

        // Attempt to register
        final result = await notifier.register(
          'guest_reg@example.com',
          'secret123',
        );

        // Should be conflict because hasLocalData is true, and lastUserId is null (guest)
        expect(result.status, AuthStatus.conflict);
        expect(container.read(authProvider).isAuthenticated, isFalse);
      },
    );

    test(
      'unlinkGoogle should call API and update state by removing google_sub',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        notifier.state = notifier.state.copyWith(
          accessToken: 'access',
          user: {
            'id': 1,
            'email': 'test@example.com',
            'google_sub': 'google_123',
          },
        );

        expect(container.read(authProvider).user?['google_sub'], 'google_123');

        final success = await notifier.unlinkGoogle('password123');
        expect(success, isTrue);
        expect(mockApi.unlinkGoogleCalled, isTrue);
        expect(container.read(authProvider).user?['google_sub'], isNull);

        final storedUser = await PrefsService.getUserData();
        expect(storedUser?['google_sub'], isNull);
      },
    );

    test(
      'unlinkApple should call API and update state by removing apple_sub',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        notifier.state = notifier.state.copyWith(
          accessToken: 'access',
          user: {
            'id': 1,
            'email': 'test@example.com',
            'apple_sub': 'apple_456',
          },
        );

        expect(container.read(authProvider).user?['apple_sub'], 'apple_456');

        final success = await notifier.unlinkApple('password123');
        expect(success, isTrue);
        expect(mockApi.unlinkAppleCalled, isTrue);
        expect(container.read(authProvider).user?['apple_sub'], isNull);

        final storedUser = await PrefsService.getUserData();
        expect(storedUser?['apple_sub'], isNull);
      },
    );

    test(
      'refreshUser should fetch updated user profile and merge it into state',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        notifier.state = notifier.state.copyWith(
          accessToken: 'access',
          user: {'id': 1, 'email': 'test@example.com'},
        );

        expect(container.read(authProvider).user?['google_sub'], isNull);

        await notifier.refreshUser();
        expect(mockApi.getMeCalled, isTrue);
        expect(container.read(authProvider).user?['google_sub'], 'google_123');
        expect(container.read(authProvider).user?['apple_sub'], 'apple_456');
      },
    );

    test(
      'late refreshUser response cannot restore a logged-out user',
      () async {
        final notifier = container.read(authProvider.notifier);
        await notifier.login('test@example.com', 'secret123');
        mockApi.getMeGate = Completer<Map<String, dynamic>>();
        final refresh = notifier.refreshUser();
        await Future<void>.delayed(Duration.zero);

        await notifier.clearSession();
        mockApi.getMeGate!.complete({
          'id': 1,
          'email': 'test@example.com',
          'display_name': 'Late User',
        });
        await refresh;

        expect(container.read(authProvider).isAuthenticated, isFalse);
        expect(await PrefsService.getUserData(), isNull);
      },
    );
  });

  group('AuthProvider backend error mapping', () {
    test('login maps a machine-readable error code to a locale key', () async {
      mockApi.loginError = ApiException(
        statusCode: 401,
        message: 'E-posta veya parola hatalı.',
        code: 'invalid_credentials',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final result = await notifier.login('test@example.com', 'wrong-pass');

      expect(result.status, AuthStatus.error);
      expect(result.errorMessage, 'auth_err_invalid_credentials');
      final state = container.read(authProvider);
      expect(state.error, 'auth_err_invalid_credentials');
      expect(state.loading, isFalse);
      expect(state.isAuthenticated, isFalse);
    });

    test(
      'login falls back to the legacy message map when the server sends no code',
      () async {
        // `code` alanı dönmeyen eski sunucu. Yedek eşleme kaldırılırsa ham
        // Türkçe sunucu metni İngilizce arayüze sızar.
        mockApi.loginError = ApiException(
          statusCode: 401,
          message: 'E-posta veya parola hatalı.',
        );
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        final result = await notifier.login('test@example.com', 'wrong-pass');

        expect(result.errorMessage, 'auth_err_invalid_credentials');
        expect(
          container.read(authProvider).error,
          'auth_err_invalid_credentials',
        );
      },
    );

    test(
      'login with an unverified email asks for verification without an error band',
      () async {
        mockApi.loginError = ApiException(
          statusCode: 403,
          message: 'E-posta adresi doğrulanmamış.',
          code: 'email_unverified',
        );
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        final result = await notifier.login('test@example.com', 'secret123');

        expect(result.status, AuthStatus.pendingVerification);
        final state = container.read(authProvider);
        expect(state.error, isNull);
        expect(state.loading, isFalse);
      },
    );

    test('login surfaces an unmapped server message verbatim', () async {
      mockApi.loginError = ApiException(
        statusCode: 500,
        message: 'Depolama alanı dolu.',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final result = await notifier.login('test@example.com', 'secret123');

      expect(result.errorMessage, 'Depolama alanı dolu.');
    });

    test('login reports a generic failure for a non-API exception', () async {
      mockApi.loginError = FakeNetworkException();
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final result = await notifier.login('test@example.com', 'secret123');

      expect(result.status, AuthStatus.error);
      expect(result.errorMessage, 'auth_err_login_failed');
      expect(container.read(authProvider).error, 'auth_err_login_failed');
    });

    test('register maps the legacy duplicate-email message', () async {
      mockApi.registerError = ApiException(
        statusCode: 409,
        message: 'Bu e-posta zaten kayıtlı.',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final result = await notifier.register('taken@example.com', 'secret123');

      expect(result.status, AuthStatus.error);
      expect(result.errorMessage, 'auth_err_email_exists');
    });

    test('verifyEmail maps a rejected code', () async {
      mockApi.verifyEmailError = ApiException(
        statusCode: 400,
        message: 'Geçersiz veya süresi dolmuş doğrulama kodu.',
        code: 'verify_code_failed',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final result = await notifier.verifyEmail('reg@example.com', '000000');

      expect(result.status, AuthStatus.error);
      expect(result.errorMessage, 'auth_err_verify_code_failed');
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });
  });

  group('AuthProvider keeps the session when the server rejects a request', () {
    test('changePassword failure leaves the user signed in', () async {
      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'secret123');
      mockApi.changePasswordError = ApiException(
        statusCode: 400,
        message: 'Mevcut parola hatalı.',
        code: 'wrong_password',
      );

      final success = await notifier.changePassword('wrong-old', 'new-secret1');

      expect(success, isFalse);
      final state = container.read(authProvider);
      expect(state.error, 'auth_err_wrong_password');
      expect(state.loading, isFalse);
      expect(state.isAuthenticated, isTrue);
      expect(await PrefsService.getAccessToken(), 'test_access');
    });

    test(
      'deleteAccount failure keeps both the session and the local data',
      () async {
        final notifier = container.read(authProvider.notifier);
        await notifier.login('test@example.com', 'secret123');
        await PrefsService.saveRating(
          movieId: 77,
          isTV: false,
          rating: 4,
          metadataLocale: 'tr',
        );
        mockApi.deleteAccountError = ApiException(
          statusCode: 403,
          message: 'Mevcut parola hatalı.',
          code: 'wrong_password',
        );

        final success = await notifier.deleteAccount('wrong-pass');

        expect(success, isFalse);
        expect(container.read(authProvider).error, 'auth_err_wrong_password');
        expect(container.read(authProvider).isAuthenticated, isTrue);
        expect(await DatabaseHelper().hasAnyLocalData(), isTrue);
      },
    );

    test('resetPassword failure leaves the user signed in', () async {
      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'secret123');
      mockApi.resetPasswordError = ApiException(
        statusCode: 400,
        message: 'Geçersiz veya süresi dolmuş doğrulama kodu.',
        code: 'verify_code_failed',
      );

      final success = await notifier.resetPassword(
        'test@example.com',
        '000000',
        'new-secret1',
      );

      expect(success, isFalse);
      expect(container.read(authProvider).error, 'auth_err_verify_code_failed');
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(await PrefsService.getAccessToken(), 'test_access');
    });

    test('unlinkGoogle failure keeps google_sub on the account', () async {
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();
      notifier.state = notifier.state.copyWith(
        accessToken: 'access',
        user: {
          'id': 1,
          'email': 'test@example.com',
          'google_sub': 'google_123',
        },
      );
      mockApi.unlinkGoogleError = ApiException(
        statusCode: 400,
        message: 'Bağlantıyı kaldırmak için parola gerekli.',
      );

      final success = await notifier.unlinkGoogle('');

      expect(success, isFalse);
      final state = container.read(authProvider);
      expect(state.error, 'auth_err_google_unlink_failed');
      expect(state.user?['google_sub'], 'google_123');
      expect(state.loading, isFalse);
    });
  });

  group('AuthProvider password reset code', () {
    test(
      'verifyResetCode reaches the server and clears the error band',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        final success = await notifier.verifyResetCode(
          'test@example.com',
          '123456',
        );

        expect(success, isTrue);
        expect(mockApi.verifyResetCodeCalled, isTrue);
        final state = container.read(authProvider);
        expect(state.loading, isFalse);
        expect(state.error, isNull);
      },
    );

    test('verifyResetCode maps a rejected code to a locale key', () async {
      mockApi.verifyResetCodeError = ApiException(
        statusCode: 400,
        message: 'Geçersiz veya süresi dolmuş doğrulama kodu.',
        code: 'verify_code_failed',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final success = await notifier.verifyResetCode(
        'test@example.com',
        '000000',
      );

      expect(success, isFalse);
      expect(container.read(authProvider).error, 'auth_err_verify_code_failed');
      expect(container.read(authProvider).loading, isFalse);
    });

    test('forgotPassword maps a rate-limit rejection', () async {
      mockApi.forgotPasswordError = ApiException(
        statusCode: 429,
        message: 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.',
      );
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();

      final success = await notifier.forgotPassword('test@example.com');

      expect(success, isFalse);
      expect(container.read(authProvider).error, 'auth_err_rate_limited');
    });
  });

  group('AuthProvider session restore and profile update', () {
    test(
      'a stored session is restored on launch and backfills the last-user id',
      () async {
        // Eski kurulumdan gelen cihaz: token + kullanıcı var ama
        // last_authenticated_user_id yazılmamış. Migration satırı düşerse
        // aynı kullanıcının bir sonraki girişi "hesap değişimi" sanılır.
        await PrefsService.saveTokens(
          accessToken: 'stored_access',
          refreshToken: 'stored_refresh',
        );
        await PrefsService.saveUserData({
          'id': 7,
          'email': 'stored@example.com',
          'display_name': 'Stored User',
        });
        await PrefsService.setLastAuthenticatedUserId(null);

        container.read(authProvider.notifier);
        await pumpEventQueue();

        final state = container.read(authProvider);
        expect(state.isAuthenticated, isTrue);
        expect(state.user?['email'], 'stored@example.com');
        expect(state.accessToken, 'stored_access');
        expect(state.loading, isFalse);
        expect(await PrefsService.getLastAuthenticatedUserId(), '7');
      },
    );

    test(
      'updateUserProfile stores the username and writes is_public as an int',
      () async {
        final notifier = container.read(authProvider.notifier);
        await notifier.login('test@example.com', 'secret123');

        await notifier.updateUserProfile('new_handle', false);

        final user = container.read(authProvider).user;
        expect(user?['username'], 'new_handle');
        expect(user?['is_public'], 0);
        final stored = await PrefsService.getUserData();
        expect(stored?['username'], 'new_handle');
        expect(stored?['is_public'], 0);
      },
    );

    test('updateUserProfile is a no-op while signed out', () async {
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();
      expect(container.read(authProvider).user, isNull);

      await notifier.updateUserProfile('ghost', true);

      expect(container.read(authProvider).user, isNull);
      expect(await PrefsService.getUserData(), isNull);
    });
  });

  group('AuthProvider cancelled conflict login', () {
    test(
      'cancelPendingLogin revokes the refresh token the server already issued',
      () async {
        // Çakışma diyaloğu iptal edilirse token çifti oturuma hiç dönüşmez;
        // iptal edilmezse sunucuda 30 gün geçerli yetim bir refresh token kalır.
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        await notifier.cancelPendingLogin({
          'access_token': 'pending_access',
          'refresh_token': 'pending_refresh',
        });

        expect(mockApi.revokedRefreshTokens, ['pending_refresh']);
        expect(container.read(authProvider).isAuthenticated, isFalse);
      },
    );

    test(
      'cancelPendingLogin skips revocation when there is no token',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        await notifier.cancelPendingLogin({'refresh_token': ''});
        await notifier.cancelPendingLogin(null);

        expect(mockApi.revokedRefreshTokens, isEmpty);
      },
    );
  });

  group('AuthProvider resilience', () {
    test('a corrupted stored session does not leave the app spinning', () async {
      // Yarım yazılmış / bozulmuş auth_user_data. jsonDecode patlar; kullanıcı
      // sonsuza kadar açılış spinner'ında kalmamalı, misafir olarak devam etmeli.
      SharedPreferences.setMockInitialValues({'auth_user_data': '{bozuk-json'});
      await PrefsService.saveTokens(
        accessToken: 'stored_access',
        refreshToken: 'stored_refresh',
      );

      container.read(authProvider.notifier);
      await pumpEventQueue();

      final state = container.read(authProvider);
      expect(state.loading, isFalse);
      expect(state.isAuthenticated, isFalse);
    });

    test(
      'logout ends the local session even if the server call fails',
      () async {
        final notifier = container.read(authProvider.notifier);
        await notifier.login('test@example.com', 'secret123');
        mockApi.logoutError = FakeNetworkException();

        await notifier.logout();

        expect(mockApi.logoutCalled, isTrue);
        expect(container.read(authProvider).isAuthenticated, isFalse);
        expect(container.read(authProvider).user, isNull);
        expect(await PrefsService.getAccessToken(), isNull);
      },
    );

    test('a failed /me refresh leaves the session untouched', () async {
      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'secret123');
      mockApi.getMeError = FakeNetworkException();

      await notifier.refreshUser();

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user?['email'], 'test@example.com');
    });

    test(
      'resendVerificationCode reports failure instead of throwing',
      () async {
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();
        mockApi.resendVerificationError = FakeNetworkException();

        final ok = await notifier.resendVerificationCode('reg@example.com');

        expect(ok, isFalse);
      },
    );

    test(
      'register reports a generic failure for a non-API exception',
      () async {
        mockApi.registerError = FakeNetworkException();
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        final result = await notifier.register('reg@example.com', 'secret123');

        expect(result.status, AuthStatus.error);
        expect(result.errorMessage, 'auth_err_register_failed');
        expect(container.read(authProvider).loading, isFalse);
      },
    );

    test(
      'verifyEmail reports a generic failure for a non-API exception',
      () async {
        mockApi.verifyEmailError = FakeNetworkException();
        final notifier = container.read(authProvider.notifier);
        await pumpEventQueue();

        final result = await notifier.verifyEmail('reg@example.com', '123456');

        expect(result.status, AuthStatus.error);
        expect(result.errorMessage, 'auth_err_verify_code_failed');
        expect(container.read(authProvider).isAuthenticated, isFalse);
      },
    );

    test('unlinkApple failure keeps apple_sub on the account', () async {
      final notifier = container.read(authProvider.notifier);
      await pumpEventQueue();
      notifier.state = notifier.state.copyWith(
        accessToken: 'access',
        user: {'id': 1, 'email': 'test@example.com', 'apple_sub': 'apple_456'},
      );
      mockApi.unlinkAppleError = ApiException(
        statusCode: 400,
        message: 'Bağlantıyı kaldırmak için parola gerekli.',
      );

      final success = await notifier.unlinkApple('');

      expect(success, isFalse);
      final state = container.read(authProvider);
      expect(state.user?['apple_sub'], 'apple_456');
      expect(state.error, isNotNull);
      expect(state.loading, isFalse);
    });
  });

  group('AuthProvider unexpected (non-API) failures', () {
    // Ağ/serileştirme gibi ApiException olmayan hatalar kullanıcıya ham
    // exception metni olarak değil, yerelleştirme anahtarı olarak dönmeli ve
    // çağrı `false` ile bitmeli — arayüz çökmemeli.
    final cases = <String, Future<bool> Function(AuthNotifier, MockApiService)>{
      'changePassword': (n, api) {
        api.changePasswordError = FakeNetworkException();
        return n.changePassword('old12345', 'new12345');
      },
      'deleteAccount': (n, api) {
        api.deleteAccountError = FakeNetworkException();
        return n.deleteAccount('secret123');
      },
      'forgotPassword': (n, api) {
        api.forgotPasswordError = FakeNetworkException();
        return n.forgotPassword('test@example.com');
      },
      'verifyResetCode': (n, api) {
        api.verifyResetCodeError = FakeNetworkException();
        return n.verifyResetCode('test@example.com', '123456');
      },
      'resetPassword': (n, api) {
        api.resetPasswordError = FakeNetworkException();
        return n.resetPassword('test@example.com', '123456', 'new12345');
      },
      'unlinkGoogle': (n, api) {
        api.unlinkGoogleError = FakeNetworkException();
        return n.unlinkGoogle('secret123');
      },
    };

    cases.forEach((name, run) {
      test('$name reports a localized error instead of throwing', () async {
        final notifier = container.read(authProvider.notifier);
        await notifier.login('test@example.com', 'secret123');

        final success = await run(notifier, mockApi);

        expect(success, isFalse);
        final state = container.read(authProvider);
        expect(state.loading, isFalse);
        expect(state.error, isNotNull);
        expect(
          state.error,
          startsWith('auth_err_'),
          reason: 'ham exception metni arayüze sızmamalı',
        );
        expect(state.isAuthenticated, isTrue);
      });
    });
  });
}
