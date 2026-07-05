class AppConfig {
  static const _defaultApiBaseUrl =
      'https://foodlabeldetective.com.tr/cinema/api';
  static const _defaultWebProfileBaseUrl =
      'https://foodlabeldetective.com.tr/cinema/profile';

  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static const _webProfileBaseUrl = String.fromEnvironment(
    'WEB_PROFILE_BASE_URL',
    defaultValue: _defaultWebProfileBaseUrl,
  );

  static String get apiBaseUrl => _trimTrailingSlash(_apiBaseUrl);
  static String get webProfileBaseUrl => _trimTrailingSlash(_webProfileBaseUrl);

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
