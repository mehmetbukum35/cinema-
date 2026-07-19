import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/social.dart';
import 'app_config.dart';
import 'crash_reporting_service.dart';
import 'prefs_service.dart';

part 'api/auth_api.dart';
part 'api/couch_api.dart';
part 'api/recommendation_api.dart';
part 'api/social_api.dart';
part 'api/sync_api.dart';

enum RefreshOutcome { success, denied, transient }

/// Shared HTTP transport for headers, retries, refresh, correlation, and errors.
class ApiClient {
  static const _kRequestTimeout = Duration(seconds: 20);
  static String get baseUrl => AppConfig.apiBaseUrl;
  final http.Client _client;
  final Duration requestTimeout;
  final Duration transientRetryDelay;
  void Function()? onSessionExpired;
  Future<RefreshOutcome>? _refreshFuture;
  ApiClient({
    http.Client? client,
    this.onSessionExpired,
    this.requestTimeout = _kRequestTimeout,
    this.transientRetryDelay = const Duration(milliseconds: 250),
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders({
    bool requireAuth = true,
    String? requestId,
  }) async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Accept-Language': PrefsService.activeLanguageCode,
    };
    if (requestId case final requestId?) {
      headers['X-Request-ID'] = requestId;
    }
    if (requireAuth) {
      final token = await PrefsService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<http.Response> _withTimeout(Future<http.Response> request) =>
      request.timeout(requestTimeout);

  bool _isTransientTransportError(Object error) =>
      error is TimeoutException ||
      error is http.ClientException ||
      error is SocketException;

  Future<http.Response> _sendTransport(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    // GET is idempotent: shared hosting may occasionally close a stale
    // keep-alive connection before sending headers, so retry transport-only
    // failures. Mutating requests are never retried to avoid duplicate writes.
    final maxAttempts = method == 'GET' ? 3 : 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (method == 'POST') {
          return await _withTimeout(
            _client.post(url, headers: headers, body: body),
          );
        }
        if (method == 'DELETE') {
          return await _withTimeout(
            _client.delete(url, headers: headers, body: body),
          );
        }
        return await _withTimeout(_client.get(url, headers: headers));
      } catch (error) {
        if (attempt == maxAttempts || !_isTransientTransportError(error)) {
          rethrow;
        }
        final delay = transientRetryDelay * attempt;
        debugPrint(
          'Transient GET failure ($attempt/$maxAttempts), retrying in '
          '${delay.inMilliseconds}ms: $error',
        );
        await Future<void>.delayed(delay);
      }
    }
    throw StateError('HTTP transport exhausted unexpectedly.');
  }

  String _newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    final requestId = _newRequestId();
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders(
      requireAuth: requireAuth,
      requestId: requestId,
    );
    final String? bodyStr = body != null ? jsonEncode(body) : null;

    http.Response response;
    try {
      response = await _sendTransport(method, url, headers, bodyStr);
    } on TimeoutException catch (e) {
      debugPrint("Network request timed out after $requestTimeout: $e");
      rethrow;
    } catch (e) {
      debugPrint("Network request error: $e");
      rethrow;
    }

    if (response.statusCode == 401 && requireAuth) {
      debugPrint("Access token expired (401). Attempting silent refresh...");
      final outcome = await _attemptTokenRefresh();
      if (outcome == RefreshOutcome.success) {
        // Retry the request with the new access token
        final newHeaders = await _getHeaders(
          requireAuth: true,
          requestId: requestId,
        );
        response = await _sendTransport(method, url, newHeaders, bodyStr);
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

    if (response.statusCode >= 500) {
      final serverRequestId = response.headers['x-request-id'] ?? requestId;
      unawaited(
        CrashReportingService.record(
          StateError('API ${response.statusCode}: $method $path'),
          StackTrace.current,
          reason: 'Backend request_id=$serverRequestId',
        ),
      );
    }

    return response;
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return {};
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Never _throwRateLimited(http.Response response) {
    String message = 'auth_err_rate_limited';
    String? code;
    try {
      final data = _decodeJsonMap(response.body);
      code = data['code'] as String?;
      final serverMsg = data['error'] as String?;
      // Yeni sunucu 'rate_limited' kodu döner; kod yoksa (eski sunucu)
      // bilinen Türkçe mesajlar yerel anahtara eşlenir, gerisi aynen geçer.
      if (code == null &&
          serverMsg != null &&
          serverMsg.isNotEmpty &&
          serverMsg != 'Çok fazla istek. Lütfen biraz sonra tekrar deneyin.' &&
          serverMsg != 'Geçici hizmet kısıtı.') {
        message = serverMsg;
      }
    } catch (_) {
      // Varsayılan anahtar kullanılır.
    }
    throw ApiException(statusCode: 429, message: message, code: code);
  }

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
        final response = await _withTimeout(
          _client.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          ),
        );

        if (response.statusCode == 200) {
          final data = _decodeJsonMap(response.body);
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
}

/// Backwards-compatible facade over focused domain APIs.
class ApiService extends ApiClient
    with AuthApi, SyncApi, SocialApi, RecommendationApi, CouchApi {
  ApiService({
    super.client,
    super.onSessionExpired,
    super.requestTimeout,
    super.transientRetryDelay,
  });
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get webProfileBaseUrl => AppConfig.webProfileBaseUrl;
  static String webProfileUrl(String username, {String lang = 'tr'}) =>
      '$webProfileBaseUrl/$username?lang=$lang';
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Sunucunun makine-okur hata anahtarı (ör. 'email_unverified'). İstemci
  /// davranışı ve yerelleştirme bu alana bağlanır; [message] yalnızca eski
  /// sunucular ve bilinmeyen hatalar için insan-okur yedektir.
  final String? code;

  ApiException({required this.statusCode, required this.message, this.code});

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}
