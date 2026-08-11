part of '../api_service.dart';

enum RefreshOutcome { success, denied, transient }

class ActivityFeedPage {
  final List<dynamic> items;
  final String? nextCursor;
  final bool hasMore;

  const ActivityFeedPage({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });
}

/// Shared HTTP transport for headers, retries, refresh, correlation, and errors.
class ApiClient {
  static const _kRequestTimeout = Duration(seconds: 20);
  static String get baseUrl => AppConfig.apiBaseUrl;
  final http.Client _client;
  final Duration requestTimeout;
  final Duration transientRetryDelay;
  void Function()? onSessionExpired;
  Future<RefreshOutcome>? _refreshFuture;
  final Map<(String, String?, String), Future<http.Response>> _inFlightGets =
      {};

  /// Aktif arayüz dili. Sunucuya `Accept-Language` olarak gider ve in-flight
  /// GET birleştirme anahtarının parçasıdır. Her istekte yeniden okunur ki
  /// kullanıcı dili değiştirdiğinde kurulum anındaki değere takılı kalmasın.
  final String Function() localeCode;

  ApiClient({
    http.Client? client,
    this.onSessionExpired,
    this.requestTimeout = _kRequestTimeout,
    this.transientRetryDelay = const Duration(milliseconds: 250),
    String Function()? localeCode,
  }) : _client = client ?? http.Client(),
       localeCode = localeCode ?? _defaultLocaleCode;

  static String _defaultLocaleCode() => 'tr';

  void _invalidateInFlightGets(String pathPrefix) {
    _inFlightGets.removeWhere(
      (key, _) => key.$3 == pathPrefix || key.$3.startsWith('$pathPrefix?'),
    );
  }

  Future<Map<String, String>> _getHeaders({
    bool requireAuth = true,
    bool optionalAuth = false,
    String? requestId,
  }) async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Accept-Language': localeCode(),
    };
    if (requestId case final requestId?) {
      headers['X-Request-ID'] = requestId;
    }
    // Token yalnızca ucun İSTEDİĞİ yerde gider. `optionalAuth` misafire de açık
    // ama girişliyken kişiselleşen uçlar içindir (ör. GET /social/profiles/top
    // → me_liked). Bunu "her isteğe ekle" diye genellemek, /auth/login ve
    // /auth/forgot-password gibi gövdeyle çalışan uçlara da bayat bir token
    // taşırdı: sunucu okumuyor, ama erişim loglarına düşüyor.
    if (requireAuth || optionalAuth) {
      final token = await PrefsAuthStorage.getAccessToken();
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
    bool optionalAuth = false,
  }) async {
    if (method != 'GET') {
      return _performRequest(
        method,
        path,
        body: body,
        requireAuth: requireAuth,
        optionalAuth: optionalAuth,
      );
    }

    // A path alone is not an identity. Account switches and locale changes can
    // happen while an older request is still in flight; never hand that
    // response to the new session/language. Optional-auth GETs still key on
    // the token so a guest coalesce cannot steal a personalized response.
    final authToken = await PrefsAuthStorage.getAccessToken();
    final key = (localeCode(), authToken, path);
    final existing = _inFlightGets[key];
    if (existing != null) {
      debugPrint('Coalescing duplicate GET $path');
      return existing;
    }
    late final Future<http.Response> request;
    request =
        _performRequest(
          method,
          path,
          body: body,
          requireAuth: requireAuth,
          optionalAuth: optionalAuth,
        ).whenComplete(() {
          if (identical(_inFlightGets[key], request)) {
            _inFlightGets.remove(key);
          }
        });
    _inFlightGets[key] = request;
    return request;
  }

  Future<http.Response> _performRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool requireAuth,
    bool optionalAuth = false,
  }) async {
    final requestId = _newRequestId();
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders(
      requireAuth: requireAuth,
      optionalAuth: optionalAuth,
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

    // optionalAuth uçları da yenilemeye dahildir: sunucu, Bearer VARSA ve
    // geçersizse 401 döner (bkz. Auth::optionalUser). Bu dal olmasaydı token
    // eskiyen kullanıcı sessizce misafir yanıtını alırdı.
    if (response.statusCode == 401 && (requireAuth || optionalAuth)) {
      // Snapshot BEFORE refresh: logout/wipe during flight also empties storage
      // and returns denied — that case must still fire onSessionExpired.
      // Only skip clear when we were already guest at the 401.
      final hadLocalSession =
          (await PrefsAuthStorage.getAccessToken()) != null ||
          (await PrefsAuthStorage.getRefreshToken()) != null ||
          (await PrefsAuthStorage.getUserData()) != null;
      debugPrint("Access token expired (401). Attempting silent refresh...");
      final outcome = await _attemptTokenRefresh();
      if (outcome == RefreshOutcome.success) {
        // Retry the request with the new access token
        final newHeaders = await _getHeaders(
          requireAuth: requireAuth,
          optionalAuth: optionalAuth,
          requestId: requestId,
        );
        response = await _sendTransport(method, url, newHeaders, bodyStr);
      } else if (outcome == RefreshOutcome.denied) {
        if (!hadLocalSession) {
          debugPrint(
            '401 with no local session (guest); skipping session clear.',
          );
        } else {
          debugPrint("Refresh token rejected by server. Ending local session.");
          await PrefsService.clearAuthData();
          onSessionExpired?.call();
        }
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
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      // Sunucu (ya da araya giren bir proxy) düz metin döndürebilir; ör. yenileme
      // reddedildikten sonra gelen "Unauthorized". Gövdeyi boş kabul et ki çağıran
      // durum koduna göre tipli ApiException fırlatsın, FormatException sızmasın.
      return {};
    }
  }

  /// JSON'da beklenen dizi alanı Map/skaler gelirse (PHP boş assoc, proxy)
  /// cast patlamasın — boş liste dön.
  List<dynamic> _asDynamicList(dynamic value) {
    if (value is List) return List<dynamic>.from(value);
    return const [];
  }

  Never _throwRateLimited(http.Response response) {
    String message = 'auth_err_rate_limited';
    String? code;
    try {
      final data = _decodeJsonMap(response.body);
      code = data['code']?.toString();
      final serverMsg = data['error']?.toString();
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

    // Yenileme boyunca çıkış yapılırsa yazdığımız token oturumu diriltmesin:
    // epoch burada, ağ turundan ÖNCE alınır (bkz. PrefsAuthStorage.saveTokens).
    final refreshEpoch = PrefsAuthStorage.tokenEpoch;

    try {
      final initialRefreshToken = await PrefsAuthStorage.getRefreshToken();
      final userData = await PrefsAuthStorage.getUserData();
      if (initialRefreshToken == null) {
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
            body: jsonEncode({'refresh_token': initialRefreshToken}),
          ),
        );

        if (response.statusCode == 200) {
          final data = _decodeJsonMap(response.body);
          final tokens = data['tokens'] is Map
              ? Map<String, dynamic>.from(data['tokens'] as Map)
              : null;
          final newAccessToken = tokens?['access_token']?.toString();
          final newRefreshToken = tokens?['refresh_token']?.toString();
          // Logout / wipe can clear auth while refresh is in flight — never
          // resurrect tokens into an empty session.
          final stillRefresh = await PrefsAuthStorage.getRefreshToken();
          final stillUser = await PrefsAuthStorage.getUserData();
          if (stillRefresh == null ||
              stillUser == null ||
              newAccessToken == null ||
              newRefreshToken == null) {
            completer.complete(RefreshOutcome.denied);
          } else if (stillRefresh != initialRefreshToken) {
            // Başka refresh veya login token yazdı. Aynı kullanıcıysa rotation OK
            // (retry storage'daki access ile); hesap değiştiyse yanlış oturumda
            // retry etme.
            final initialId = userData?['id'];
            final stillId = stillUser['id'];
            if (initialId != null && initialId == stillId) {
              completer.complete(RefreshOutcome.success);
            } else {
              completer.complete(RefreshOutcome.transient);
            }
          } else {
            await PrefsAuthStorage.saveTokens(
              accessToken: newAccessToken,
              refreshToken: newRefreshToken,
              expectedEpoch: refreshEpoch,
            );
            completer.complete(RefreshOutcome.success);
          }
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
