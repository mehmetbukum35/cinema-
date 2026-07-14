import 'package:flutter/foundation.dart';

class AppConfig {
  static const _defaultApiBaseUrl = 'https://cinema.mbkm.com.tr/api';
  static const _defaultWebProfileBaseUrl = 'https://cinema.mbkm.com.tr/profile';

  static const _apiBaseUrlDefined = bool.hasEnvironment('API_BASE_URL');
  static const _webProfileBaseUrlDefined = bool.hasEnvironment(
    'WEB_PROFILE_BASE_URL',
  );

  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static const _webProfileBaseUrl = String.fromEnvironment(
    'WEB_PROFILE_BASE_URL',
    defaultValue: _defaultWebProfileBaseUrl,
  );

  // Google Sign-In: sunucu doğrulaması için ID token'ın "aud" hedefi olan
  // WEB client ID (Google Cloud Console > Credentials > OAuth 2.0 > Web).
  // Backend Config.php'deki google.client_ids ile AYNI değer olmalı.
  // Boş bırakılırsa login ekranındaki Google butonu gizlenir.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '925394401867-pkgskofm1romudrtlhap7hauerbkvesm.apps.googleusercontent.com',
  );

  static bool get googleSignInConfigured => googleServerClientId.isNotEmpty;

  static String get apiBaseUrl => _trimTrailingSlash(_apiBaseUrl);
  static String get webProfileBaseUrl => _trimTrailingSlash(_webProfileBaseUrl);

  /// Debug/profile builds should not silently hit production without an
  /// explicit `--dart-define=API_BASE_URL=...`.
  static void warnIfProductionApiWithoutDefine() {
    if (kReleaseMode) return;
    if (!_apiBaseUrlDefined && _apiBaseUrl == _defaultApiBaseUrl) {
      debugPrint(
        'WARNING [AppConfig]: Using production API ($_defaultApiBaseUrl) in '
        '${kProfileMode ? "profile" : "debug"} mode without '
        '--dart-define=API_BASE_URL. Pass a local/staging URL for development.',
      );
      assert(() {
        debugPrint(
          'TIP: flutter run --dart-define=API_BASE_URL=http://localhost:8000',
        );
        return true;
      }());
    }
    if (!_webProfileBaseUrlDefined &&
        _webProfileBaseUrl == _defaultWebProfileBaseUrl) {
      debugPrint(
        'WARNING [AppConfig]: Using production web profile URL in '
        '${kProfileMode ? "profile" : "debug"} mode without '
        '--dart-define=WEB_PROFILE_BASE_URL.',
      );
    }
  }

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
