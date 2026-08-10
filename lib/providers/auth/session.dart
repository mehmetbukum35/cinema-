part of '../auth_provider.dart';

mixin AuthSessionMixin on Notifier<AuthState> {
  Completer<void> get _sessionReady;
  ApiService get _apiService;
  Future<void> _initSession() async {
    state = state.copyWith(loading: true);
    try {
      final token = await PrefsAuthStorage.getAccessToken();
      final userData = await PrefsAuthStorage.getUserData();
      if (!ref.mounted) return;
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
          await PrefsAuthStorage.setLastAuthenticatedUserId(currentUserId);
        }

        Future(() async {
          await Future.wait([
            ref.read(watchlistProvider.notifier).load(),
            ref.read(statsProvider.notifier).load(),
          ]);
          await Future.wait([
            ref.read(socialProvider.notifier).loadFriends(),
            ref.read(socialProvider.notifier).loadActivityFeed(),
            ref.read(socialProvider.notifier).loadRecommendations(),
            ref.read(socialProvider.notifier).loadSentRecommendations(),
            ref.read(socialProvider.notifier).loadReceivedRecommendations(),
            ref.read(socialProvider.notifier).loadTopProfiles(),
          ]);
        });
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (e, st) {
      debugPrint("Error restoring session: $e\n$st");
      if (!ref.mounted) return;
      state = state.copyWith(loading: false);
    } finally {
      if (!_sessionReady.isCompleted) {
        _sessionReady.complete();
      }
    }
  }

  /// Sunucudan gelen {user, tokens} yanıtını oturuma çevirir: farklı hesaptan
  /// kalan yerel veri varsa çakışma döner, yoksa girişi tamamlar.
  /// login / register / Google / verifyEmail ortak son adımı.
  // ignore: unused_element — consumed by AuthEmailMixin / AuthSocialMixin.
  Future<AuthResult> _finalizeAuth(Map<String, dynamic> data) async {
    final user = data['user'] as Map<String, dynamic>;
    final tokens = data['tokens'] as Map<String, dynamic>;

    final newUserId = user['id']?.toString();
    final lastUserId = await PrefsAuthStorage.getLastAuthenticatedUserId();
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

  /// Completes the login process once conflict is resolved or when no conflict is present.
  Future<void> completeLogin({
    required Map<String, dynamic> user,
    required Map<String, dynamic> tokens,
    required ConflictResolution resolution,
  }) async {
    state = state.copyWith(loading: true);

    final previousUserId = await PrefsAuthStorage.getLastAuthenticatedUserId();
    final newUserId = user['id']?.toString();
    final accountSwitched =
        previousUserId != null &&
        newUserId != null &&
        previousUserId != newUserId;

    if (resolution == ConflictResolution.delete || accountSwitched) {
      if (resolution == ConflictResolution.delete) {
        await DatabaseHelper().hardClearAllData();
      }
      // Önceki hesabın kültür tercihleri / DNA cache'i yeni oturuma sızmasın.
      await PrefsService.clearAccountScopedPreferences();
    }
    // Set sync timestamps to 0 so we fetch/push appropriately on new login session
    await PrefsSyncMeta.setLastSyncTime(0);
    await PrefsSyncMeta.setLastPushTime(0);

    await PrefsAuthStorage.saveTokens(
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
    );
    await PrefsAuthStorage.saveUserData(user);

    await PrefsAuthStorage.setLastAuthenticatedUserId(newUserId);

    state = state.copyWith(
      accessToken: tokens['access_token'] as String,
      user: user,
      loading: true,
      loadingMessageKey: 'auth_syncing_data',
    );

    try {
      await _postAuthSessionRestore();
    } finally {
      state = state.copyWith(loading: false, loadingMessageKey: null);
    }

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
    if (AuthNotifier._googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint("Google sign-out after cancel failed (ignored): $e");
      }
    }
  }

  /// Giriş/kayıt sonrası buluttan çek + yerel provider'ları yenile.
  Future<void> _postAuthSessionRestore() async {
    ref.invalidate(socialProvider);
    // Logout path Top 20'yi invalidate eder; login da etmeli — aksi halde
    // misafir listesi / hardClear sonrası hayalet Top 20 kalır.
    ref.invalidate(topListProvider);
    // Giriş ekranını yalnızca temel bulut eşitlemesi bekletsin. Sosyal uçlardan
    // biri yavaşladığında/yanıt vermediğinde kullanıcı girişte sonsuza kadar
    // spinner arkasında kalmamalı.
    await ref.read(syncProvider.notifier).performSync();
    ref.invalidate(watchlistProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(topListProvider);

    unawaited(
      Future.wait([
        ref.read(socialProvider.notifier).loadFriends(),
        ref.read(socialProvider.notifier).loadActivityFeed(),
        ref.read(socialProvider.notifier).loadRecommendations(),
        ref.read(socialProvider.notifier).loadSentRecommendations(),
        ref.read(socialProvider.notifier).loadReceivedRecommendations(),
        ref.read(socialProvider.notifier).loadTopProfiles(),
      ]).catchError((Object error, StackTrace stackTrace) {
        debugPrint('Post-login social refresh failed: $error\n$stackTrace');
        return <void>[];
      }),
    );
    await ref.read(recommendationEngineProvider).invalidateCache();
    ref.invalidate(swipeProvider);
    // Buluttan gelen puan/liste + arkadaş sinyalleri Keşfet'i besler.
    ref.read(browseRefreshTriggerProvider.notifier).fire();
  }

  Future<void> _invalidateGuestProviders() async {
    ref.invalidate(watchlistProvider);
    ref.invalidate(statsProvider);
    ref.invalidate(topListProvider);
    ref.invalidate(swipeProvider);
    ref.invalidate(socialProvider);
    ref.invalidate(couchProvider);
    await ref.read(recommendationEngineProvider).invalidateCache();
    ref.read(browseRefreshTriggerProvider.notifier).fire();
  }

  /// Oturumu kapatır. [wipeLocalData] true ise cihazdaki puan/liste verisi silinir.
  Future<void> _endLocalSession({required bool wipeLocalData}) async {
    state = AuthState();
    ref.read(syncProvider.notifier).resetForSessionChange();
    await NotificationService.instance.invalidateLocalToken();
    await PrefsService.clearAuthData();
    if (wipeLocalData) {
      await DatabaseHelper().hardClearAllData();
      await PrefsService.clearAccountScopedPreferences();
      await PrefsAuthStorage.setLastAuthenticatedUserId(null);
    }
    await _invalidateGuestProviders();
    ref.read(syncProvider.notifier).resetStatus();
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
    if (AuthNotifier._googleInitialized) {
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
      if (AuthNotifier._googleInitialized) {
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

  Future<void> refreshUser() async {
    if (!state.isAuthenticated) return;
    final requestedUserId = state.user?['id']?.toString();
    try {
      final userData = await _apiService.getMe();
      if (!ref.mounted ||
          !state.isAuthenticated ||
          state.user?['id']?.toString() != requestedUserId) {
        return;
      }
      final user = Map<String, dynamic>.from(state.user ?? {});
      user.addAll(userData);
      await PrefsAuthStorage.saveUserData(user);
      if (ref.mounted) {
        state = state.copyWith(user: user);
      }
    } catch (e, st) {
      debugPrint("Failed to refresh user profile from /me: $e\n$st");
    }
  }

  // Update profile user data locally
  Future<void> updateUserProfile(String username, bool isPublic) async {
    if (state.user != null) {
      final updatedUser = Map<String, dynamic>.from(state.user!);
      updatedUser['username'] = username;
      updatedUser['is_public'] = isPublic ? 1 : 0;
      await PrefsAuthStorage.saveUserData(updatedUser);
      state = state.copyWith(user: updatedUser);
    }
  }
}
