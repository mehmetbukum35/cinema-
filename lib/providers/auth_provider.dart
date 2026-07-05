import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/notification_service.dart';
import 'watchlist_provider.dart';
import 'swipe_provider.dart';

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
  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final data = await _apiService.login(email: email, password: password);
      final user = data['user'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;

      await PrefsService.saveTokens(
        accessToken: tokens['access_token'] as String,
        refreshToken: tokens['refresh_token'] as String,
      );
      await PrefsService.saveUserData(user);

      // Reset local sync timestamp to 0 so we fetch all server data on first sync
      await PrefsService.setLastSyncTime(0);

      state = state.copyWith(
        accessToken: tokens['access_token'] as String,
        user: user,
        loading: false,
      );

      // Trigger initial sync to pull remote data
      _ref.read(watchlistProvider.notifier).load();
      _ref.read(statsProvider.notifier).load();

      // Giriş sonrası FCM token'ını sunucuya kaydet.
      NotificationService.instance.registerToken();

      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Giriş yapılamadı. Lütfen bağlantınızı kontrol edin.',
      );
      return false;
    }
  }

  // POST /auth/register
  Future<bool> register(
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

      await PrefsService.saveTokens(
        accessToken: tokens['access_token'] as String,
        refreshToken: tokens['refresh_token'] as String,
      );
      await PrefsService.saveUserData(user);
      await PrefsService.setLastSyncTime(0);

      state = state.copyWith(
        accessToken: tokens['access_token'] as String,
        user: user,
        loading: false,
      );

      // Trigger initial sync
      _ref.read(watchlistProvider.notifier).load();
      _ref.read(statsProvider.notifier).load();

      // Kayıt sonrası FCM token'ını sunucuya kaydet.
      NotificationService.instance.registerToken();

      return true;
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Kayıt yapılamadı. Lütfen bağlantınızı kontrol edin.',
      );
      return false;
    }
  }

  // POST /auth/logout
  Future<void> logout() async {
    state = state.copyWith(loading: true);
    // Çıkmadan önce bu cihazın token'ını sunucudan sil (artık bildirim almasın).
    await NotificationService.instance.unregisterToken();
    try {
      await _apiService.logout();
    } catch (e, st) {
      debugPrint("Auth notifier logout request failed: $e\n$st");
    }
    await PrefsService.clearAuthData();
    await DatabaseHelper().hardClearAllData();
    state = AuthState(); // Reset auth state to defaults

    // Refresh UI providers to update content
    _ref.invalidate(watchlistProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(swipeProvider);
  }

  Future<void> clearSession() async {
    await PrefsService.clearAuthData();
    await DatabaseHelper().hardClearAllData();
    state = AuthState(); // Reset auth state to defaults

    // Refresh UI providers to update content
    _ref.invalidate(watchlistProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(swipeProvider);
  }

  // DELETE /me
  Future<bool> deleteAccount() async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.deleteAccount();
      await DatabaseHelper().hardClearAllData();
      state = AuthState();

      _ref.invalidate(watchlistProvider);
      _ref.invalidate(statsProvider);
      _ref.invalidate(swipeProvider);
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
      await DatabaseHelper().hardClearAllData();
      state = AuthState();

      _ref.invalidate(watchlistProvider);
      _ref.invalidate(statsProvider);
      _ref.invalidate(swipeProvider);
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
