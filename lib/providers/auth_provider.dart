import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/prefs/auth_storage.dart';
import '../services/prefs/library_facade.dart';
import '../services/prefs/sync_meta.dart';
import '../services/prefs_service.dart';
import '../services/db_helper.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../services/localization_service.dart';
import '../screens/login_screen.dart';
import '../widgets/app_toast.dart';
import 'watchlist_provider.dart';
import 'top_list_provider.dart';
import 'swipe_provider.dart';
import 'social_provider.dart';
import 'couch_provider.dart';
import '../services/providers.dart';

part 'auth/session.dart';
part 'auth/email_auth.dart';
part 'auth/social_sign_in.dart';
part 'auth/account.dart';
part 'auth/password_reset.dart';

enum AuthStatus { success, conflict, error, cancelled, pendingVerification }

enum ConflictResolution { merge, delete }

/// Misafirken biriken ve girişte hesaba taşınan yerel verinin özeti.
/// Sayılar birleştirmeden ÖNCE okunur: `_postAuthSessionRestore` sync'i
/// tetikliyor ve sunucudan gelen kayıtlar sayıları değiştirebiliyor.
class MergedGuestData {
  final int ratingCount;
  final int watchlistCount;

  const MergedGuestData({
    required this.ratingCount,
    required this.watchlistCount,
  });

  bool get isEmpty => ratingCount == 0 && watchlistCount == 0;
}

class AuthResult {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? tokens;
  final String? errorMessage;

  /// Yalnızca misafir verisi hesaba taşındığında dolu; aksi halde null.
  final MergedGuestData? mergedGuestData;

  AuthResult({
    required this.status,
    this.user,
    this.tokens,
    this.errorMessage,
    this.mergedGuestData,
  });
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

class AuthNotifier extends Notifier<AuthState>
    with
        AuthSessionMixin,
        AuthEmailMixin,
        AuthSocialMixin,
        AuthAccountMixin,
        AuthPasswordResetMixin {
  static bool _googleInitialized = false;

  /// Testler sahte API'yi buradan enjekte eder; uretimde apiServiceProvider.
  final ApiService? _apiOverride;

  /// Verilirse oturum diskten okunmaz ve state bu degerle acilir — widget
  /// testleri gercek AuthNotifier'i (dolayisiyla gercek metotlarini) hazir bir
  /// oturumla kurabilsin diye.
  final AuthState? initialState;

  @override
  // `late final` DEGIL: Riverpod 3'te invalidate/rebuild ayni notifier ornegi
  // uzerinde build()'i yeniden kosar, ikinci atama LateInitializationError verir.
  late ApiService _apiService;
  @override
  final Completer<void> _sessionReady = Completer<void>();

  AuthNotifier({ApiService? api, this.initialState}) : _apiOverride = api;

  @override
  AuthState build() {
    _apiService = _apiOverride ?? ref.watch(apiServiceProvider);
    _apiService.onSessionExpired = clearSession;
    NotificationService.instance.setAuthReadyHandler(
      () => _sessionReady.future,
    );
    NotificationService.instance.setLocaleSource(
      () => ref.read(localeProvider).languageCode,
    );
    // Push bildirim dinleyicilerini bir kez kur (best-effort).
    NotificationService.instance.init(_apiService);
    ref.onDispose(() {
      NotificationService.instance.setAuthReadyHandler(null);
      NotificationService.instance.setLocaleSource(null);
      if (!_sessionReady.isCompleted) {
        _sessionReady.complete();
      }
    });
    final seeded = initialState;
    if (seeded != null) {
      if (!_sessionReady.isCompleted) _sessionReady.complete();
      return seeded;
    }
    // build() donmeden state'e yazilamaz; oturum okuma ilk mikro gorevde.
    Future.microtask(_initSession);
    return AuthState();
  }

  /// Sunucu hatasını yerel metin anahtarına çevirir. Önce makine-okur `code`
  /// alanına bakılır (yeni sözleşme); kod yoksa eski sunucularla uyum için
  /// Türkçe mesaj eşlemesine düşülür ([_mapBackendError]).
  @override
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
}

final apiServiceProvider = Provider<ApiService>((ref) {
  // Sağlayıcı her istekte okunur; dil değişince yeni istekler yeni dili alır.
  return ApiService(localeCode: () => ref.read(localeProvider).languageCode);
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
