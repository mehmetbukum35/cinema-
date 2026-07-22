import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/notification_service.dart';
import '../services/localization_service.dart';
import '../screens/login_screen.dart';
import '../widgets/app_toast.dart';
import 'watchlist_provider.dart';
import 'top_list_provider.dart';
import 'swipe_provider.dart';
import 'social_provider.dart';
import '../services/providers.dart';

enum AuthStatus { success, conflict, error, cancelled, pendingVerification }

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
  final String? loadingMessageKey;
  final Map<String, dynamic>? user; // contains id, email, display_name
  final String? error;
  final String? accessToken;

  AuthState({
    this.loading = false,
    this.loadingMessageKey,
    this.user,
    this.error,
    this.accessToken,
  });

  bool get isAuthenticated => user != null && accessToken != null;
  bool get isLoggedIn => isAuthenticated;

  // `error` ve `loadingMessageKey` için sentinel deseni
  static const Object _unset = Object();

  AuthState copyWith({
    bool? loading,
    Object? loadingMessageKey = _unset,
    Map<String, dynamic>? user,
    Object? error = _unset,
    String? accessToken,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      loadingMessageKey: identical(loadingMessageKey, _unset)
          ? this.loadingMessageKey
          : loadingMessageKey as String?,
      user: user ?? this.user,
      error: identical(error, _unset) ? this.error : error as String?,
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

  /// Sunucu hatasını yerel metin anahtarına çevirir. Önce makine-okur `code`
  /// alanına bakılır (yeni sözleşme); kod yoksa eski sunucularla uyum için
  /// Türkçe mesaj eşlemesine düşülür ([_mapBackendError]).
  String _mapApiError(ApiException e) {
    const codeMap = {
      'email_exists': 'auth_err_email_exists',
      'invalid_credentials': 'auth_err_invalid_credentials',
      'email_invalid': 'auth_forgot_err_email_invalid',
      'password_too_short': 'auth_forgot_err_pass_length',
      'wrong_password': 'auth_err_wrong_password',
      'user_not_found': 'auth_err_user_not_found',
      'google_failed': 'auth_err_google_failed',
      'google_unlink_failed': 'auth_err_google_unlink_failed',
      'apple_failed': 'auth_err_apple_failed',
      'verify_code_failed': 'auth_err_verify_code_failed',
      'email_unverified': 'auth_err_email_unverified',
      'rate_limited': 'auth_err_rate_limited',
    };
    final mapped = codeMap[e.code];
    if (mapped != null) return mapped;
    return _mapBackendError(e.message);
  }

  /// ESKİ sözleşme: sunucunun Türkçe mesajlarını birebir eşler. Yalnızca
  /// `code` alanı dönmeyen (güncellenmemiş) sunucular için yedektir; yeni
  /// eşlemeler buraya değil _mapApiError'daki codeMap'e eklenmelidir.
  String _mapBackendError(String message) {
    final clean = message.trim();
    switch (clean) {
      case 'Bu e-posta zaten kayıtlı.':
        return 'auth_err_email_exists';
      case 'E-posta veya parola hatalı.':
        return 'auth_err_invalid_credentials';
      case 'Geçersiz e-posta.':
      case 'Geçersiz e-posta formatı.':
      case 'E-posta adresi gerekli.':
        return 'auth_forgot_err_email_invalid';
      case 'Parola en az 8 karakter olmalı.':
      case 'Yeni parola en az 8 karakter olmalı.':
        return 'auth_forgot_err_pass_length';
      case 'Mevcut parola hatalı.':
        return 'auth_err_wrong_password';
      case 'Kullanıcı bulunamadı.':
        return 'auth_err_user_not_found';
      case 'Google kimliği doğrulanamadı.':
        return 'auth_err_google_failed';
      case 'Bağlı Google hesabı yok.':
      case 'Bağlantıyı kaldırmak için parola gerekli.':
        return 'auth_err_google_unlink_failed';
      case 'Geçersiz veya süresi dolmuş doğrulama kodu.':
        return 'auth_err_verify_code_failed';
      case 'E-posta adresi doğrulanmamış.':
        return 'auth_err_email_unverified';
      case 'Giriş başarısız.':
        return 'auth_err_login_failed';
      case 'Kayıt başarısız.':
        return 'auth_err_register_failed';
      case 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.':
      case 'Geçici hizmet kısıtı.':
        return 'auth_err_rate_limited';
      default:
        return message;
    }
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

        Future(() async {
          await Future.wait([
            _ref.read(watchlistProvider.notifier).load(),
            _ref.read(statsProvider.notifier).load(),
          ]);
          await Future.wait([
            _ref.read(socialProvider.notifier).loadFriends(),
            _ref.read(socialProvider.notifier).loadActivityFeed(),
            _ref.read(socialProvider.notifier).loadRecommendations(),
            _ref.read(socialProvider.notifier).loadSentRecommendations(),
            _ref.read(socialProvider.notifier).loadReceivedRecommendations(),
            _ref.read(socialProvider.notifier).loadTopProfiles(),
          ]);
        });
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (e, st) {
      debugPrint("Error restoring session: $e\n$st");
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  /// Sunucudan gelen {user, tokens} yanıtını oturuma çevirir: farklı hesaptan
  /// kalan yerel veri varsa çakışma döner, yoksa girişi tamamlar.
  /// login / register / Google / verifyEmail ortak son adımı.
  Future<AuthResult> _finalizeAuth(Map<String, dynamic> data) async {
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
  }

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

  static bool _googleInitialized = false;

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
      if (!_googleInitialized) {
        await signIn.initialize(serverClientId: AppConfig.googleServerClientId);
        _googleInitialized = true;
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
      if (!mounted) {
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
    // Set sync timestamps to 0 so we fetch/push appropriately on new login session
    await PrefsService.setLastSyncTime(0);
    await PrefsService.setLastPushTime(0);

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

  /// Çakışma diyaloğunda "Girişi İptal Et" seçildiğinde çağrılır: sunucunun
  /// çoktan verdiği token çifti yerel oturuma hiç dönüşmeyeceği için refresh
  /// token sunucuda iptal edilir (aksi halde 30 gün geçerli yetim token kalır).
  /// Google ile girilmişse Google oturumu da kapatılır ki bir sonraki denemede
  /// hesap seçici yeniden açılsın.
  Future<void> cancelPendingLogin(Map<String, dynamic>? tokens) async {
    final refreshToken = tokens?['refresh_token'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _apiService.revokeRefreshToken(refreshToken);
    }
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint("Google sign-out after cancel failed (ignored): $e");
      }
    }
  }

  /// Giriş/kayıt sonrası buluttan çek + yerel provider'ları yenile.
  Future<void> _postAuthSessionRestore() async {
    _ref.invalidate(socialProvider);
    // Logout path Top 20'yi invalidate eder; login da etmeli — aksi halde
    // misafir listesi / hardClear sonrası hayalet Top 20 kalır.
    _ref.invalidate(topListProvider);
    await Future.wait([
      _ref.read(watchlistProvider.notifier).load(),
      _ref.read(statsProvider.notifier).load(),
    ]);
    await Future.wait([
      _ref.read(socialProvider.notifier).loadFriends(),
      _ref.read(socialProvider.notifier).loadActivityFeed(),
      _ref.read(socialProvider.notifier).loadRecommendations(),
      _ref.read(socialProvider.notifier).loadSentRecommendations(),
      _ref.read(socialProvider.notifier).loadReceivedRecommendations(),
      _ref.read(socialProvider.notifier).loadTopProfiles(),
    ]);
    await _ref.read(recommendationEngineProvider).invalidateCache();
    _ref.invalidate(swipeProvider);
    // Buluttan gelen puan/liste + arkadaş sinyalleri Keşfet'i besler.
    _ref.read(browseRefreshTriggerProvider.notifier).state++;
  }

  Future<void> _invalidateGuestProviders() async {
    _ref.invalidate(watchlistProvider);
    _ref.invalidate(statsProvider);
    _ref.invalidate(topListProvider);
    _ref.invalidate(swipeProvider);
    _ref.invalidate(socialProvider);
    await _ref.read(recommendationEngineProvider).invalidateCache();
    _ref.read(browseRefreshTriggerProvider.notifier).state++;
  }

  /// Oturumu kapatır. [wipeLocalData] true ise cihazdaki puan/liste verisi silinir.
  Future<void> _endLocalSession({required bool wipeLocalData}) async {
    state = AuthState();
    await NotificationService.instance.invalidateLocalToken();
    await PrefsService.clearAuthData();
    if (wipeLocalData) {
      await DatabaseHelper().hardClearAllData();
      await PrefsService.setLastAuthenticatedUserId(null);
    }
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

  /// Tehlike bölgesi "tüm verileri sıfırla". Sıralama önemli:
  /// 1) bellekteki oturum kapanır ki bu sırada 401'e düşen bir istek
  ///    [clearSession] üzerinden "oturum süresi doldu" uyarısı basamasın,
  /// 2) push token sunucudan silinir (token'lar depoda hâlâ geçerliyken —
  ///    depo silindikten sonra bu istek 401 → refresh denied → sahte
  ///    "Giriş Yap" uyarısı üretiyordu),
  /// 3) depolama temizlenir.
  Future<void> wipeAllData() async {
    final wasLoggedIn = state.isAuthenticated;
    state = AuthState();
    if (wasLoggedIn) {
      await NotificationService.instance.unregisterToken();
      await NotificationService.instance.invalidateLocalToken();
      if (_googleInitialized) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (e) {
          debugPrint("Google sign-out after data wipe failed (ignored): $e");
        }
      }
    }
    await PrefsService.resetAll();
    await _invalidateGuestProviders();
  }

  Future<void> clearSession() async {
    // Kullanıcı zaten çıkmışsa (ör. veri sıfırlama/hesap silme sonrası havada
    // kalan bir isteğin 401'i) uyarı basma; depo ilgili akışta zaten temizlendi.
    if (!state.isAuthenticated) return;

    await _endLocalSession(wipeLocalData: false);

    final context = NotificationService.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    showAppSnackBar(
      context,
      AppLocalizations.of(context)?.get('session_expired_message') ??
          'Oturumunuz sona erdi. Verileriniz bu cihazda güvende. Tekrar giriş yapın.',
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 5),
      actionLabel:
          AppLocalizations.of(context)?.get('auth_title_login') ?? 'Giriş Yap',
      onAction: () {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
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
      final mapped = _mapApiError(e);
      state = state.copyWith(loading: false, error: mapped);
      return false;
    } catch (e, st) {
      debugPrint("Account deletion failed: $e\n$st");
      state = state.copyWith(loading: false, error: 'auth_err_delete_failed');
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

  Future<void> refreshUser() async {
    if (!state.isAuthenticated) return;
    try {
      final userData = await _apiService.getMe();
      final user = Map<String, dynamic>.from(state.user ?? {});
      user.addAll(userData);
      await PrefsService.saveUserData(user);
      if (mounted) {
        state = state.copyWith(user: user);
      }
    } catch (e, st) {
      debugPrint("Failed to refresh user profile from /me: $e\n$st");
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
