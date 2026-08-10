part of '../auth_provider.dart';

mixin AuthEmailMixin on Notifier<AuthState> {
  ApiService get _apiService;
  Future<AuthResult> _finalizeAuth(Map<String, dynamic> data);
  String _mapApiError(ApiException e);
  // POST /auth/login
  Future<AuthResult> login(String email, String password) async {
    state = state.copyWith(
      loading: true,
      loadingMessageKey: 'auth_signing_in_email',
      error: null,
    );
    try {
      final data = await _apiService.login(email: email, password: password);
      return await _finalizeAuth(data);
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      if (mapped == 'auth_err_email_unverified') {
        // Parola doğru ama kayıt kodla doğrulanmamış → istemci doğrulama
        // ekranını açar; hata bandı gösterilmez.
        state = state.copyWith(loading: false, error: null);
        return AuthResult(status: AuthStatus.pendingVerification);
      }
      state = state.copyWith(loading: false, error: mapped);
      return AuthResult(status: AuthStatus.error, errorMessage: mapped);
    } catch (e) {
      const errMsg = 'auth_err_login_failed';
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
    state = state.copyWith(
      loading: true,
      loadingMessageKey: 'auth_signing_in_email',
      error: null,
    );
    try {
      final data = await _apiService.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (data['pending_verification'] == true) {
        // Yeni akış: kod e-postalandı, oturum verifyEmail ile açılacak.
        state = state.copyWith(loading: false);
        return AuthResult(status: AuthStatus.pendingVerification);
      }
      // Eski sunucu davranışı (doğrudan token) — geriye dönük uyumluluk.
      return await _finalizeAuth(data);
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return AuthResult(status: AuthStatus.error, errorMessage: mapped);
    } catch (e) {
      const errMsg = 'auth_err_register_failed';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  // POST /auth/verify-email — kayıttaki kodu doğrular, oturumu açar.
  Future<AuthResult> verifyEmail(String email, String code) async {
    state = state.copyWith(
      loading: true,
      loadingMessageKey: 'auth_signing_in_email',
      error: null,
    );
    try {
      final data = await _apiService.verifyEmail(email, code);
      return await _finalizeAuth(data);
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return AuthResult(status: AuthStatus.error, errorMessage: mapped);
    } catch (e) {
      const errMsg = 'auth_err_verify_code_failed';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  // POST /auth/resend-verification — doğrulama kodunu yeniden gönderir.
  Future<bool> resendVerificationCode(String email) async {
    try {
      await _apiService.resendVerification(email);
      return true;
    } catch (e) {
      debugPrint("Resend verification failed: $e");
      return false;
    }
  }
}
