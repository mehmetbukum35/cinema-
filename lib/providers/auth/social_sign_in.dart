part of '../auth_provider.dart';

mixin AuthSocialMixin on Notifier<AuthState> {
  ApiService get _apiService;
  Future<AuthResult> _finalizeAuth(Map<String, dynamic> data);
  String _mapApiError(ApiException e);

  /// Google Sign-In (v7 API): Google kimliği doğrular, ID token'ı backend'e
  /// gönderir; oturum yine bizim JWT/refresh boru hattımızla kurulur.
  /// Hesap çakışması olursa e-posta girişindeki AYNI conflict akışı çalışır.
  Future<AuthResult> signInWithGoogle() async {
    if (!AppConfig.googleSignInConfigured) {
      const errMsg = 'auth_err_google_not_configured';
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
    state = state.copyWith(
      loading: true,
      loadingMessageKey: 'auth_signing_in_google',
      error: null,
    );
    try {
      final signIn = GoogleSignIn.instance;
      if (!AuthNotifier._googleInitialized) {
        await signIn.initialize(serverClientId: AppConfig.googleServerClientId);
        AuthNotifier._googleInitialized = true;
      }

      final GoogleSignInAccount account;
      try {
        account = await signIn.authenticate(
          scopeHint: const ['email', 'openid', 'profile'],
        );
      } on GoogleSignInException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'GoogleSignInException: code=${e.code.name} '
            'description=${e.description}',
          );
        }
        // Kullanıcı vazgeçti → hata değil; ekran sessizce devam eder.
        if (e.code == GoogleSignInExceptionCode.canceled) {
          state = state.copyWith(loading: false);
          return AuthResult(status: AuthStatus.cancelled);
        }
        rethrow;
      }

      // Hesap seçici kapandı — kullanıcı tekrar uygulamada; yükleme UI'ını
      // yeniden tetikle (loading zaten true olsa da yeni state ataması repaint'i
      // garanti eder).
      if (!ref.mounted) {
        return AuthResult(status: AuthStatus.cancelled);
      }
      state = state.copyWith(
        loading: true,
        loadingMessageKey: 'auth_signing_in_google',
        error: null,
      );

      final idToken = account.authentication.idToken;
      if (kDebugMode) {
        debugPrint(
          'Google idToken: ${idToken == null ? "NULL" : "present (${idToken.length} chars)"}',
        );
      }
      if (idToken == null) {
        throw Exception('auth_err_google_token_failed');
      }

      final data = await _apiService.loginWithGoogle(idToken);
      return await _finalizeAuth(data);
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Google backend login failed: HTTP ${e.statusCode} — ${e.message}',
        );
        if (e.statusCode == 401) {
          debugPrint(
            'Google 401 ipucu: sunucu Config.php → google.client_ids içinde '
            'Web client ID olmalı (aud): ${AppConfig.googleServerClientId}',
          );
        } else if (e.statusCode == 500 &&
            e.message.contains('google.client_ids eksik')) {
          debugPrint(
            'Google 500 ipucu: Config.php dosyasında google.client_ids '
            'bloğu tanımlı değil.',
          );
        }
      }
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return AuthResult(status: AuthStatus.error, errorMessage: mapped);
    } catch (e) {
      debugPrint("Google sign-in failed: $e");
      final errMsg = e.toString().contains('auth_err_google_token_failed')
          ? 'auth_err_google_token_failed'
          : 'auth_err_google_failed';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }

  /// Sign in with Apple (yalnızca iOS'ta gösterilir): Apple kimliği doğrular,
  /// identity token'ı backend'e gönderir; oturum yine bizim JWT/refresh boru
  /// hattımızla kurulur. Ad-soyad yalnızca İLK yetkilendirmede gelir ve
  /// backend'e display_name olarak iletilir.
  Future<AuthResult> signInWithApple() async {
    state = state.copyWith(
      loading: true,
      loadingMessageKey: 'auth_signing_in_apple',
      error: null,
    );
    try {
      final AuthorizationCredentialAppleID credential;
      try {
        credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
      } on SignInWithAppleAuthorizationException catch (e) {
        // Kullanıcı vazgeçti → hata değil; ekran sessizce devam eder.
        if (e.code == AuthorizationErrorCode.canceled) {
          state = state.copyWith(loading: false);
          return AuthResult(status: AuthStatus.cancelled);
        }
        rethrow;
      }

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('auth_err_apple_token_failed');
      }

      final name = [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().join(' ').trim();

      final data = await _apiService.loginWithApple(
        idToken,
        displayName: name.isEmpty ? null : name,
      );
      return await _finalizeAuth(data);
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Apple backend login failed: HTTP ${e.statusCode} — ${e.message}',
        );
      }
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return AuthResult(status: AuthStatus.error, errorMessage: mapped);
    } catch (e) {
      debugPrint("Apple sign-in failed: $e");
      final errMsg = e.toString().contains('auth_err_apple_token_failed')
          ? 'auth_err_apple_token_failed'
          : 'auth_err_apple_failed';
      state = state.copyWith(loading: false, error: errMsg);
      return AuthResult(status: AuthStatus.error, errorMessage: errMsg);
    }
  }
}
