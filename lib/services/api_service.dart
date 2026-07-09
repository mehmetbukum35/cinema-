import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'prefs_service.dart';
import '../models/social.dart';

/// Refresh denemesinin sonucu:
/// - [success]: yeni token çifti alındı, istek yeniden denenebilir.
/// - [denied]: sunucu refresh token'ı REDDETTİ (401/403/422) → oturum gerçekten
///   bitti, yerel oturum temizlenmeli.
/// - [transient]: ağ/sunucu hatası (timeout, 5xx…) → token hâlâ geçerli
///   olabilir; oturum ASLA düşürülmez, istek başarısız bırakılır.
enum RefreshOutcome { success, denied, transient }

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get webProfileBaseUrl => AppConfig.webProfileBaseUrl;

  /// Web profil URL'i. Uygulama diline göre ?lang=en|tr eklenir.
  static String webProfileUrl(String username, {String lang = 'tr'}) =>
      '$webProfileBaseUrl/$username?lang=$lang';
  final http.Client _client;
  void Function()? onSessionExpired;
  Future<RefreshOutcome>? _refreshFuture;

  ApiService({http.Client? client, this.onSessionExpired})
    : _client = client ?? http.Client();

  // Helper to construct headers with optional authorization bearer token
  Future<Map<String, String>> _getHeaders({bool requireAuth = true}) async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requireAuth) {
      final token = await PrefsService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // Base HTTP request wrapper with automatic 401 handling (token refresh)
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders(requireAuth: requireAuth);
    final String? bodyStr = body != null ? jsonEncode(body) : null;

    http.Response response;
    try {
      if (method == 'POST') {
        response = await _client.post(url, headers: headers, body: bodyStr);
      } else if (method == 'DELETE') {
        response = await _client.delete(url, headers: headers, body: bodyStr);
      } else {
        response = await _client.get(url, headers: headers);
      }
    } catch (e) {
      debugPrint("Network request error: $e");
      rethrow;
    }

    if (response.statusCode == 401 && requireAuth) {
      debugPrint("Access token expired (401). Attempting silent refresh...");
      final outcome = await _attemptTokenRefresh();
      if (outcome == RefreshOutcome.success) {
        // Retry the request with the new access token
        final newHeaders = await _getHeaders(requireAuth: true);
        if (method == 'POST') {
          response = await _client.post(
            url,
            headers: newHeaders,
            body: bodyStr,
          );
        } else if (method == 'DELETE') {
          response = await _client.delete(
            url,
            headers: newHeaders,
            body: bodyStr,
          );
        } else {
          response = await _client.get(url, headers: newHeaders);
        }
      } else if (outcome == RefreshOutcome.denied) {
        debugPrint("Refresh token rejected by server. Ending local session.");
        // Clear local auth session so the app returns to logged-out state
        await PrefsService.clearAuthData();
        onSessionExpired?.call();
      } else {
        // Geçici hata: oturuma DOKUNMA. Refresh token büyük olasılıkla hâlâ
        // geçerli; bu isteği 401 olarak döndürüp bir sonraki denemeye bırak.
        debugPrint("Refresh failed transiently; keeping session intact.");
      }
    }

    if (response.statusCode == 429) {
      _throwRateLimited(response);
    }

    return response;
  }

  Never _throwRateLimited(http.Response response) {
    String message = 'auth_err_rate_limited';
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final serverMsg = data['error'] as String?;
        if (serverMsg ==
                'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.' ||
            serverMsg == 'Geçici hizmet kısıtı.') {
          message = 'auth_err_rate_limited';
        } else if (serverMsg != null && serverMsg.isNotEmpty) {
          message = serverMsg;
        }
      }
    } catch (_) {
      // Varsayılan anahtar kullanılır.
    }
    throw ApiException(statusCode: 429, message: message);
  }

  // Attempts to refresh access token using the stored refresh token
  Future<RefreshOutcome> _attemptTokenRefresh() async {
    if (_refreshFuture != null) {
      debugPrint(
        "Token refresh already in progress, awaiting existing future...",
      );
      return _refreshFuture!;
    }

    final completer = Completer<RefreshOutcome>();
    _refreshFuture = completer.future;

    try {
      final refreshToken = await PrefsService.getRefreshToken();
      final userData = await PrefsService.getUserData();
      if (refreshToken == null) {
        if (userData != null) {
          debugPrint(
            "Refresh token is null but user data exists. Treating as transient storage failure.",
          );
          completer.complete(RefreshOutcome.transient);
        } else {
          completer.complete(RefreshOutcome.denied);
        }
      } else {
        final url = Uri.parse('$baseUrl/auth/refresh');
        final response = await _client.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final tokens = data['tokens'] as Map<String, dynamic>;
          await PrefsService.saveTokens(
            accessToken: tokens['access_token'] as String,
            refreshToken: tokens['refresh_token'] as String,
          );
          completer.complete(RefreshOutcome.success);
        } else if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 422) {
          // Sunucu token'ı tanımadı/reddetti → oturum gerçekten geçersiz.
          completer.complete(RefreshOutcome.denied);
        } else {
          // 5xx vb. → sunucu tarafı sorun; oturumu düşürme.
          completer.complete(RefreshOutcome.transient);
        }
      }
    } catch (e) {
      debugPrint("Token refresh call failed: $e");
      completer.complete(RefreshOutcome.transient);
    } finally {
      _refreshFuture = null;
    }

    return completer.future;
  }

  // ─── Auth Endpoints ──────────────────────────────────────────────────────────

  // POST /auth/register
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
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Kayıt başarısız.',
      );
    }
  }

  // POST /auth/login
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
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Giriş başarısız.',
      );
    }
  }

  // POST /auth/google — Google ID token'ı ile giriş/kayıt (sunucu doğrular,
  // hesabı bulur/bağlar/oluşturur ve bizim JWT çiftimizi döner).
  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await _request(
      'POST',
      '/auth/google',
      body: {'id_token': idToken},
      requireAuth: false,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_google_failed',
      );
    }
  }

  // POST /auth/logout
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

  /// Henüz yerel oturuma dönüşmemiş bir token çiftini sunucuda iptal eder
  /// (çakışma diyaloğunda "Girişi İptal Et" seçilirse yetim refresh token
  /// kalmasın diye). Best-effort: hata yutulur.
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

  // DELETE /me (Delete Account)
  Future<void> deleteAccount() async {
    final response = await _request('DELETE', '/me', requireAuth: true);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Hesap silinemedi.',
      );
    }
    await PrefsService.clearAuthData();
  }

  // POST /auth/change-password
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Parola değiştirilemedi.',
      );
    }
    await PrefsService.clearAuthData();
  }

  // ─── Sync Endpoints ──────────────────────────────────────────────────────────

  // GET /sync?since=<unix_ms>
  Future<Map<String, dynamic>> pull(int since) async {
    final response = await _request(
      'GET',
      '/sync?since=$since',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ??
            'Veri senkronizasyonu (pull) başarısız.',
      );
    }
  }

  // POST /sync
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    final response = await _request(
      'POST',
      '/sync',
      body: payload,
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ??
            'Veri senkronizasyonu (push) başarısız.',
      );
    }
  }

  // DELETE /search-history (Clear search history remotely)
  Future<void> clearRemoteSearchHistory() async {
    final response = await _request(
      'DELETE',
      '/search-history',
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ?? 'Arama geçmişi sunucudan silinemedi.',
      );
    }
  }

  // DELETE /sync (Reset remote sync data)
  Future<void> clearRemoteSyncData() async {
    final response = await _request('DELETE', '/sync', requireAuth: true);
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Bulut verileri sıfırlanamadı.',
      );
    }
  }

  // POST /auth/forgot-password
  Future<void> forgotPassword(String email) async {
    final response = await _request(
      'POST',
      '/auth/forgot-password',
      body: {'email': email},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Sıfırlama kodu gönderilemedi.',
      );
    }
  }

  // POST /auth/verify-reset-code
  Future<void> verifyResetCode(String email, String code) async {
    final response = await _request(
      'POST',
      '/auth/verify-reset-code',
      body: {'email': email, 'code': code},
      requireAuth: false,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Doğrulama kodu geçersiz.',
      );
    }
  }

  // POST /auth/reset-password
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Şifre sıfırlanamadı.',
      );
    }
  }

  // Not: eski GET /config/tmdb ucu (ve bu metodun eski karşılığı) kaldırıldı.
  // TMDB istekleri artık TmdbService üzerinden doğrudan backend proxy'sine
  // (/tmdb/*) gidiyor; anahtar hiçbir zaman client'a indirilmiyor.

  // ─── SOSYAL AĞ & ARKADAŞLIK METODLARI ─────────────────────────────────────

  // POST /social/profile/setup
  Future<Map<String, dynamic>> setupProfile(
    String username,
    bool isPublic,
  ) async {
    final response = await _request(
      'POST',
      '/social/profile/setup',
      body: {'username': username, 'is_public': isPublic ? 1 : 0},
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Profil ayarları güncellenemedi.',
      );
    }
  }

  // POST /social/device/register — FCM token'ını sunucuya kaydeder.
  Future<void> registerDevice(String token, {String? platform}) async {
    final response = await _request(
      'POST',
      '/social/device/register',
      body: {'token': token, 'platform': platform},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Cihaz kaydedilemedi.',
      );
    }
  }

  // POST /social/device/unregister — çıkışta token'ı siler.
  Future<void> unregisterDevice(String token) async {
    final response = await _request(
      'POST',
      '/social/device/unregister',
      body: {'token': token},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Cihaz kaydı silinemedi.',
      );
    }
  }

  // GET /social/friends
  Future<Map<String, dynamic>> getFriends() async {
    final response = await _request(
      'GET',
      '/social/friends',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaş listesi alınamadı.',
      );
    }
  }

  // POST /social/friends/request
  Future<Map<String, dynamic>> sendFriendRequest(String searchQuery) async {
    final response = await _request(
      'POST',
      '/social/friends/request',
      body: {'search_query': searchQuery},
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaşlık isteği gönderilemedi.',
      );
    }
  }

  // POST /social/friends/accept
  Future<void> acceptFriendRequest(int friendId) async {
    final response = await _request(
      'POST',
      '/social/friends/accept',
      body: {'friend_id': friendId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'İstek kabul edilemedi.',
      );
    }
  }

  // POST /social/friends/reject
  Future<void> rejectFriendRequest(int friendId) async {
    final response = await _request(
      'POST',
      '/social/friends/reject',
      body: {'friend_id': friendId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaşlık silinemedi.',
      );
    }
  }

  // GET /social/friends/activity
  Future<List<dynamic>> getActivityFeed({int? friendId}) async {
    final path = friendId != null
        ? '/social/friends/activity?friend_id=$friendId'
        : '/social/friends/activity';
    final response = await _request('GET', path, requireAuth: true);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data['activity'] as List<dynamic>;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Aktivite akışı alınamadı.',
      );
    }
  }

  // GET /social/match/watchlist-intersection/{friend_id}
  Future<List<dynamic>> getWatchlistIntersection(int friendId) async {
    final response = await _request(
      'GET',
      '/social/match/watchlist-intersection/$friendId',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data['watchlist'] as List<dynamic>;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Ortak izleme listesi alınamadı.',
      );
    }
  }

  // GET /social/friends/signals
  Future<FriendSignals> getFriendSignals() async {
    final response = await _request(
      'GET',
      '/social/friends/signals',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return FriendSignals.fromJson(
        data['signals'] as Map<String, dynamic>? ?? const {},
      );
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaş sinyalleri alınamadı.',
      );
    }
  }

  // DELETE /auth/google/link — Google hesabı bağlantısını kaldırır.
  Future<void> unlinkGoogle({required String password}) async {
    final response = await _request(
      'DELETE',
      '/auth/google/link',
      body: {'password': password},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'auth_err_google_unlink_failed',
      );
    }
  }

  // POST /social/dna — Sinema DNA snapshot'ını yayınlar (public web kartı için).
  Future<void> publishTasteDna(Map<String, dynamic> snapshot) async {
    final response = await _request(
      'POST',
      '/social/dna',
      body: {'dna': snapshot},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'DNA yayınlanamadı.',
      );
    }
  }

  // GET /social/match/taste/{friend_id}
  Future<Map<String, dynamic>> getTasteMatch(int friendId) async {
    final response = await _request(
      'GET',
      '/social/match/taste/$friendId',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Uyum skoru alınamadı.',
      );
    }
  }

  // POST /social/recommend
  Future<void> recommendToFriend({
    required int friendId,
    required int movieId,
    required bool isTv,
    required String title,
    String? posterPath,
    String? note,
  }) async {
    final response = await _request(
      'POST',
      '/social/recommend',
      body: {
        'friend_id': friendId,
        'movie_id': movieId,
        'is_tv': isTv ? 1 : 0,
        'title': title,
        'poster_path': ?posterPath,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Öneri gönderilemedi.',
      );
    }
  }

  // GET /social/recommendations
  Future<Map<String, dynamic>> getRecommendations() async {
    final response = await _request(
      'GET',
      '/social/recommendations',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Öneriler alınamadı.',
      );
    }
  }

  // POST /social/recommendations/seen
  Future<void> markRecommendationsSeen() async {
    final response = await _request(
      'POST',
      '/social/recommendations/seen',
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'İşaretlenemedi.',
      );
    }
  }

  // GET /social/profiles/top — en çok beğeni alan 20 herkese açık üye.
  Future<Map<String, dynamic>> getTopProfiles() async {
    final response = await _request(
      'GET',
      '/social/profiles/top',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Popüler listeler alınamadı.',
    );
  }

  // POST /social/profile/like — üye profilini beğen / beğeniyi geri al.
  // Sunucunun döndürdüğü güncel like_count değerini verir.
  Future<int> likeProfile(int ownerId, bool liked) async {
    final response = await _request(
      'POST',
      '/social/profile/like',
      body: {'owner_id': ownerId, 'liked': liked},
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return int.tryParse(data['like_count']?.toString() ?? '') ?? 0;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Beğeni gönderilemedi.',
    );
  }

  // GET /social/title-reviews/{type}/{id}
  Future<Map<String, dynamic>> getTitleReviews(String type, int id) async {
    final response = await _request(
      'GET',
      '/social/title-reviews/$type/$id',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Yorumlar yüklenemedi.',
    );
  }

  // GET /titles/{type}/{id}/score — cinema+ üyelerinin topluluk skoru
  Future<Map<String, dynamic>> getTitleScore(String type, int id) async {
    final response = await _request(
      'GET',
      '/titles/$type/$id/score',
      requireAuth: true,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Skor yüklenemedi.',
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}
