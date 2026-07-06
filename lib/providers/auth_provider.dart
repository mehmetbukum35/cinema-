import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/notification_service.dart';
import '../services/localization_service.dart';
import '../screens/login_screen.dart';
import 'watchlist_provider.dart';
import 'swipe_provider.dart';
import 'social_provider.dart';
import '../services/providers.dart';

enum AuthStatus { success, conflict, error, cancelled }

enum ConflictResolution { merge, delete }

class AuthResult {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? tokens;
  final String? errorMessage;

  AuthResult({required this.status, this.user, this.tokens, this.errorMessage});
}

class AuthState {
  final bool loading;
  final Map<String, dynamic>? user; // contains id, email, display_name
  final String? error;
  final String? accessToken;

  AuthState({this.loading = false, this.user, this.error, this.accessToken});

  bool get isAuthenticated => user != null && accessToken != null;
  bool get isLoggedIn => isAuthenticated;

  AuthState copyWith({
    bool? loading,
    Map<String, dynamic>? user,
    String? error,
    String? accessToken,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      user: user ?? this.user,
      error: error ?? this.error,
      accessToken: accessToken ?? this.accessToken,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _apiService;
  final Ref _ref;

  AuthNotifier(this._apiService, this._ref) : super(AuthState()) {
    _apiService.onSessionExpired = clearSession;
    // Push bildirim dinleyicilerini bir kez kur (best-effort).
    NotificationService.instance.init(_apiService);
    _initSession();
  }

  // Restore session from local storage on launch
  Future<void> _initSession() async {
    state = state.copyWith(loading: true);
    try {
      final token = await PrefsService.getAccessToken();
      final userData = await PrefsService.getUserData();
      if (!mounted) return;
      if (token != null && userData != null) {
        state = state.copyWith(
          accessToken: token,
          user: userData,
          loading: false,
        );
        // Oturum geri yüklendi → bu cihazın FCM token'ını sunucuya kaydet.
        NotificationService.instance.registerToken();

        // Migration: Ensure last_authenticated_user_id is set
        final currentUserId = userData['id']?.toString();
        if (currentUserId != null) {
          await PrefsService.setLastAuthenticatedUserId(currentUserId);
        }

        _ref.read(watchlistProvider.notifier).load();
        _ref.read(statsProvider.notifier).load();
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (e, st) {
      debugPrint("Error restoring session: $e\n$st");
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  // POST /auth/login
  Future<AuthResult> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final data = await _apiService.login(email: email, password: password);
      final user = data['user'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;

      final newUserId = user['id']?.toString();
      final lastUserId = await PrefsService.getLastAuthenticatedUserId();
      final hasLocalData = await DatabaseHelper().hasAnyLocalData();

      if (hasLocalData && (lastUserId == null || lastUserId != newUserId)) {
        state = state.copyWith(loading: false);
        return AuthResult(
          status: AuthStatus.conflict,
          user: user,
          tokens: tokens,
        );
      }

      await completeLogin(
        user: user,
        tokens: tokens,
        resolution: ConflictResolution.merge,
      );
      return AuthResult(status: AuthStatus.success);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return AuthResult(status: AuthStatus.error, errorMessage: e.message);
    } catch (e) {
      const errMsg = 'Giriş yapılamadı. Lütfen bağlantınızı kontrol edin.';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  // POST /auth/register
  Future<AuthResult> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final data = await _apiService.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      final user = data['user'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;

      final newUserId = user['id']?.toString();
      final lastUserId = await PrefsService.getLastAuthenticatedUserId();
      final hasLocalData = await DatabaseHelper().hasAnyLocalData();

      if (hasLocalData && (lastUserId == null || lastUserId != newUserId)) {
        state = state.copyWith(loading: false);
        return AuthResult(
          status: AuthStatus.conflict,
          user: user,
          tokens: tokens,
        );
      }

      await completeLogin(
        user: user,
        tokens: tokens,
        resolution: ConflictResolution.merge,
      );
      return AuthResult(status: AuthStatus.success);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return AuthResult(status: AuthStatus.error, errorMessage: e.message);
    } catch (e) {
      const errMsg = 'Kayıt yapılamadı. Lütfen bağlantınızı kontrol edin.';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  static bool _googleInitialized = false;

  /// Google Sign-In (v7 API): Google kimliği doğrular, ID token'ı backend'e
  /// gönderir; oturum yine bizim JWT/refresh boru hattımızla kurulur.
  /// Hesap çakışması olursa e-posta girişindeki AYNI conflict akışı çalışır.
  Future<AuthResult> signInWithGoogle() async {
    if (!AppConfig.googleSignInConfigured) {
      const errMsg = 'Google girişi bu derlemede yapılandırılmamış.';
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
    state = state.copyWith(loading: true, error: null);
    try {
      final signIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await signIn.initialize(serverClientId: AppConfig.googleServerClientId);
        _googleInitialized = true;
      }

      final GoogleSignInAccount account;
      try {
        account = await signIn.authenticate(scopeHint: const ['email']);
      } on GoogleSignInException catch (e) {
        // Kullanıcı vazgeçti → hata değil; ekran sessizce devam eder.
        if (e.code == GoogleSignInExceptionCode.canceled) {
          state = state.copyWith(loading: false);
          return AuthResult(status: AuthStatus.cancelled);
        }
        rethrow;
      }

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google ID token alınamadı (serverClientId doğru mu?)');
      }

      final data = await _apiService.loginWithGoogle(idToken);
      final user = data['user'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;

      final newUserId = user['id']?.toString();
      final lastUserId = await PrefsService.getLastAuthenticatedUserId();
      final hasLocalData = await DatabaseHelper().hasAnyLocalData();

      if (hasLocalData && (lastUserId == null || lastUserId != newUserId)) {
        state = state.copyWith(loading: false);
        return AuthResult(
          status: AuthStatus.conflict,
          user: user,
          tokens: tokens,
        );
      }

      await completeLogin(
        user: user,
        tokens: tokens,
        resolution: ConflictResolution.merge,
      );
      return AuthResult(status: AuthStatus.success);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return AuthResult(status: AuthStatus.error, errorMessage: e.message);
    } catch (e) {
      debugPrint("Google sign-in failed: $e");
      const errMsg = 'Google ile giriş yapılamadı. Lütfen tekrar deneyin.';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  /// Completes the login process once conflict is resolved or when no conflict is present.
  Future<void> completeLogin({
    required Map<String, dynamic> user,
    required Map<String, dynamic> tokens,
    required ConflictResolution resolution,
  }) async {
    state = state.copyWith(loading: true);

    if (resolution == ConflictResolution.delete) {
      await DatabaseHelper().hardClearAllData();
    }
    // Set sync timestamp to 0 so we fetch/push appropriately on new login session
    await PrefsService.setLastSyncTime(0);

    await PrefsService.saveTokens(
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
    );
    await PrefsService.saveUserData(user);

    final newUserId = user['id']?.toString();
    await PrefsService.setLastAuthenticatedUserId(newUserId);

    state = state.copyWith(
      accessToken: tokens['access_token'] as String,
      user: user,
      loading: false,
    );

    await _postAuthSessionRestore();

    // Giriş sonrası FCM token'ını sunucuya kaydet.
    NotificationService.instance.registerToken();
  }

  /// Giriş/kayıt sonrası buluttan çek + yerel provider'ları yenile.
  Future<void> _postAuthSessionRestore() async {
    await Future.wait([
      _ref.read(watchlistProvider.notifier).load(),
      _ref.read(statsProvider.notifier).load(),
    ]);
    await _ref.read(recommendationEngineProvider).invalidateCache();
    _ref.invalidate(swipeProvider);
  }

  Future<void> _invalidateGuestProviders() async {
    _ref.invalidate(watchlistProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(swipeProvider);
    _ref.invalidate(socialProvider);
    await _ref.read(recommendationEngineProvider).invalidateCache();
  }

  /// Oturumu kapatır. [wipeLocalData] true ise cihazdaki puan/liste verisi silinir.
  Future<void> _endLocalSession({required bool wipeLocalData}) async {
    await PrefsService.clearAuthData();
    if (wipeLocalData) {
      await DatabaseHelper().hardClearAllData();
      await PrefsService.setLastAuthenticatedUserId(null);
    }
    state = AuthState();
    await _invalidateGuestProviders();
  }

  // POST /auth/logout
  /// [wipeLocalData]: kullanıcı "bu cihazdaki verileri de sil" seçtiyse true.
  Future<void> logout({bool wipeLocalData = false}) async {
    state = state.copyWith(loading: true);
    await NotificationService.instance.unregisterToken();
    try {
      await _apiService.logout();
    } catch (e, st) {
      debugPrint("Auth notifier logout request failed: $e\n$st");
    }
    // Google oturumu da kapansın ki sonraki girişte hesap seçici açılsın.
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint("Google sign-out failed (ignored): $e");
      }
    }
    await _endLocalSession(wipeLocalData: wipeLocalData);
  }

  Future<void> clearSession() async {
    await _endLocalSession(wipeLocalData: false);

    final context = NotificationService.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)?.get('session_expired_message') ??
              'Oturumunuz sona erdi. Verileriniz bu cihazda güvende. Tekrar giriş yapın.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label:
              AppLocalizations.of(context)?.get('auth_title_login') ??
              'Giriş Yap',
          textColor: Colors.white,
          onPressed: () {
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          },
        ),
      ),
    );
  }

  // DELETE /me
  Future<bool> deleteAccount() async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.deleteAccount();
      await _endLocalSession(wipeLocalData: true);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e, st) {
      debugPrint("Account deletion failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'Hesap silinemedi. Lütfen tekrar deneyin.',
      );
      return false;
    }
  }

  // POST /auth/change-password
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      // Sunucu tüm oturumları düşürür; api_service clearAuthData çağırır.
      // Yerel SQLite korunur — yeniden girişte sync birleştirir.
      await _endLocalSession(wipeLocalData: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e, st) {
      debugPrint("Change password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'Parola değiştirilemedi. Lütfen tekrar deneyin.',
      );
      return false;
    }
  }

  // POST /auth/forgot-password
  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.forgotPassword(email);
      state = state.copyWith(loading: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e, st) {
      debugPrint("Forgot password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error:
            'Sıfırlama kodu gönderilemedi. Lütfen bağlantınızı kontrol edin.',
      );
      return false;
    }
  }

  // POST /auth/verify-reset-code
  Future<bool> verifyResetCode(String email, String code) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.verifyResetCode(email, code);
      state = state.copyWith(loading: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e, st) {
      debugPrint("Verify reset code failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'Doğrulama kodu geçersiz. Lütfen tekrar deneyin.',
      );
      return false;
    }
  }

  // POST /auth/reset-password
  Future<bool> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.resetPassword(email, code, newPassword);
      state = AuthState(); // reset to default logged-out state
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e, st) {
      debugPrint("Reset password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'Şifre sıfırlanamadı. Lütfen tekrar deneyin.',
      );
      return false;
    }
  }

  // Update profile user data locally
  Future<void> updateUserProfile(String username, bool isPublic) async {
    if (state.user != null) {
      final updatedUser = Map<String, dynamic>.from(state.user!);
      updatedUser['username'] = username;
      updatedUser['is_public'] = isPublic ? 1 : 0;
      await PrefsService.saveUserData(updatedUser);
      state = state.copyWith(user: updatedUser);
    }
  }
}

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AuthNotifier(apiService, ref);
});
