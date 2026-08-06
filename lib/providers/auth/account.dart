part of '../auth_provider.dart';

mixin AuthAccountMixin on StateNotifier<AuthState> {
  ApiService get _apiService;
  String _mapApiError(ApiException e);
  Future<void> _endLocalSession({required bool wipeLocalData});
  // DELETE /me
  Future<bool> deleteAccount(String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.deleteAccount(password);
      await _endLocalSession(wipeLocalData: true);
      return true;
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Account deletion failed: $e\n$st");
      state = state.copyWith(loading: false, error: 'auth_err_delete_failed');
      return false;
    }
  }

  Future<bool> deleteAccountWithSocialProvider(String provider) async {
    state = state.copyWith(loading: true, error: null);
    try {
      late final String identityToken;
      if (provider == 'google') {
        final signIn = GoogleSignIn.instance;
        if (!AuthNotifier._googleInitialized) {
          await signIn.initialize(
            serverClientId: AppConfig.googleServerClientId,
          );
          AuthNotifier._googleInitialized = true;
        }
        final account = await signIn.authenticate(
          scopeHint: const ['email', 'openid', 'profile'],
        );
        identityToken = account.authentication.idToken ?? '';
      } else if (provider == 'apple') {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [AppleIDAuthorizationScopes.email],
        );
        identityToken = credential.identityToken ?? '';
      } else {
        throw ArgumentError.value(provider, 'provider');
      }
      if (identityToken.isEmpty) {
        throw StateError('Missing social identity token.');
      }
      await _apiService.deleteAccountWithProvider(
        provider: provider,
        identityToken: identityToken,
      );
      await _endLocalSession(wipeLocalData: true);
      return true;
    } catch (e, st) {
      debugPrint("Social account deletion failed: $e\n$st");
      if (mounted) {
        state = state.copyWith(loading: false, error: 'auth_err_delete_failed');
      }
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
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Change password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_change_pass_failed',
      );
      return false;
    }
  }

  // DELETE /auth/google/link
  Future<bool> unlinkGoogle(String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.unlinkGoogle(password: password);
      final user = Map<String, dynamic>.from(state.user ?? {});
      user.remove('google_sub');
      await PrefsService.saveUserData(user);
      state = state.copyWith(loading: false, user: user);
      return true;
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Google unlink failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_google_unlink_failed',
      );
      return false;
    }
  }

  Future<bool> unlinkGoogleWithReauth(String newPassword) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final signIn = GoogleSignIn.instance;
      if (!AuthNotifier._googleInitialized) {
        await signIn.initialize(serverClientId: AppConfig.googleServerClientId);
        AuthNotifier._googleInitialized = true;
      }
      final account = await signIn.authenticate(
        scopeHint: const ['email', 'openid', 'profile'],
      );
      final token = account.authentication.idToken;
      if (token == null) throw StateError('Missing Google identity token.');
      await _apiService.unlinkGoogleWithIdentityToken(token, newPassword);
      await _finishProviderUnlink('google_sub');
      return true;
    } catch (e, st) {
      debugPrint("Google reauth unlink failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_google_unlink_failed',
      );
      return false;
    }
  }

  // DELETE /auth/apple/link
  Future<bool> unlinkApple(String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.unlinkApple(password: password);
      final user = Map<String, dynamic>.from(state.user ?? {});
      user.remove('apple_sub');
      await PrefsService.saveUserData(user);
      state = state.copyWith(loading: false, user: user);
      return true;
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Apple unlink failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_apple_unlink_failed',
      );
      return false;
    }
  }

  Future<bool> unlinkAppleWithReauth(String newPassword) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
      );
      final token = credential.identityToken;
      if (token == null) throw StateError('Missing Apple identity token.');
      await _apiService.unlinkAppleWithIdentityToken(token, newPassword);
      await _finishProviderUnlink('apple_sub');
      return true;
    } catch (e, st) {
      debugPrint("Apple reauth unlink failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_apple_unlink_failed',
      );
      return false;
    }
  }

  Future<void> _finishProviderUnlink(String key) async {
    final user = Map<String, dynamic>.from(state.user ?? {});
    user.remove(key);
    await PrefsService.saveUserData(user);
    state = state.copyWith(loading: false, user: user);
  }
}
