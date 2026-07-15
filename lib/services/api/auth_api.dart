part of '../api_service.dart';

/// Authentication and account backend operations.
mixin AuthApi on ApiClient {
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final body = {
      'email': email,
      'password': password,
      'display_name': displayName,
    };
    final response = await _request(
      'POST',
      '/auth/register',
      body: body,
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Kayıt başarısız.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final response = await _request(
      'POST',
      '/auth/verify-email',
      body: {'email': email, 'code': code},
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Doğrulama kodu geçersiz.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> resendVerification(String email) async {
    final response = await _request(
      'POST',
      '/auth/resend-verification',
      body: {'email': email},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Doğrulama kodu gönderilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final body = {'email': email, 'password': password};
    final response = await _request(
      'POST',
      '/auth/login',
      body: body,
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Giriş başarısız.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await _request(
      'POST',
      '/auth/google',
      body: {'id_token': idToken},
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_google_failed',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> loginWithApple(
    String identityToken, {
    String? displayName,
  }) async {
    final response = await _request(
      'POST',
      '/auth/apple',
      body: {
        'identity_token': identityToken,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_apple_failed',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> logout() async {
    final refreshToken = await PrefsService.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _request(
          'POST',
          '/auth/logout',
          body: {'refresh_token': refreshToken},
          requireAuth: false,
        );
      } catch (e, st) {
        // Oturumu kapatırken sunucu çağrısı başarısız olsa bile yerel verileri temizlemeye devam ediyoruz.
        debugPrint("Sunucu logout isteği başarısız oldu: $e\n$st");
      }
    }
    await PrefsService.clearAuthData();
  }

  Future<void> revokeRefreshToken(String refreshToken) async {
    try {
      await _request(
        'POST',
        '/auth/logout',
        body: {'refresh_token': refreshToken},
        requireAuth: false,
      );
    } catch (e) {
      debugPrint("Refresh token revoke failed (ignored): $e");
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _request('GET', '/me', requireAuth: true);
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,

        message: data['error'] as String? ?? 'Profil alınamadı.',
        code: data['code'] as String?,
      );
    }
    return _decodeJsonMap(response.body);
  }

  Future<void> deleteAccount() async {
    final response = await _request('DELETE', '/me', requireAuth: true);
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Hesap silinemedi.',
        code: data['code'] as String?,
      );
    }
    await PrefsService.clearAuthData();
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final body = {'old_password': oldPassword, 'new_password': newPassword};
    final response = await _request(
      'POST',
      '/auth/change-password',
      body: body,
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Parola değiştirilemedi.',
        code: data['code'] as String?,
      );
    }
    await PrefsService.clearAuthData();
  }

  Future<void> forgotPassword(String email) async {
    final response = await _request(
      'POST',
      '/auth/forgot-password',
      body: {'email': email},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Sıfırlama kodu gönderilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> verifyResetCode(String email, String code) async {
    final response = await _request(
      'POST',
      '/auth/verify-reset-code',
      body: {'email': email, 'code': code},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Doğrulama kodu geçersiz.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    final response = await _request(
      'POST',
      '/auth/reset-password',
      body: {'email': email, 'code': code, 'new_password': newPassword},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Şifre sıfırlanamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> unlinkGoogle({required String password}) async {
    final response = await _request(
      'DELETE',
      '/auth/google/link',
      body: {'password': password},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_google_unlink_failed',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> unlinkApple({required String password}) async {
    final response = await _request(
      'DELETE',
      '/auth/apple/link',
      body: {'password': password},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_apple_unlink_failed',
        code: data['code'] as String?,
      );
    }
  }
}
