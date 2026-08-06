part of '../auth_provider.dart';

mixin AuthPasswordResetMixin on StateNotifier<AuthState> {
  ApiService get _apiService;
  String _mapApiError(ApiException e);
  Future<void> _endLocalSession({required bool wipeLocalData});
  // POST /auth/forgot-password
  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _apiService.forgotPassword(email);
      state = state.copyWith(loading: false);
      return true;
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Forgot password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_forgot_send_failed',
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
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Verify reset code failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_verify_code_failed',
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
      // Reset, sunucudaki tüm refresh token'ları iptal eder. Mevcut access token
      // hâlâ kısa süre geçerliyken cihaz kaydını kaldır; ardından normal güvenli
      // oturum kapatma yolu FCM token'ını ve hesaba bağlı provider'ları temizlesin.
      await NotificationService.instance.unregisterToken();
      await _endLocalSession(wipeLocalData: false);
      return true;
    } on ApiException catch (e) {
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Reset password failed: $e\n$st");
      state = state.copyWith(
        loading: false,
        error: 'auth_err_reset_pass_failed',
      );
      return false;
    }
  }
}
