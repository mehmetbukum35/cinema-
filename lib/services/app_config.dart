class AppConfig {
  static const _defaultApiBaseUrl =
      'https://cinema.mbkm.com.tr/api';
  static const _defaultWebProfileBaseUrl =
      'https://cinema.mbkm.com.tr/profile';

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
    defaultValue: '',
  );

  static bool get googleSignInConfigured => googleServerClientId.isNotEmpty;

  static String get apiBaseUrl => _trimTrailingSlash(_apiBaseUrl);
  static String get webProfileBaseUrl => _trimTrailingSlash(_webProfileBaseUrl);

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
