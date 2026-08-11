import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsAuthStorage {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyAccessToken = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyUserData = 'auth_user_data';
  static const _keyLastAuthenticatedUserId = 'last_authenticated_user_id';

  // Secure storage okumak (özellikle Android Keystore) her HTTP isteğinde
  // pahalı; access token bellekte cache'lenir. saveTokens/clearTokens günceller.
  static String? _cachedAccessToken;

  /// clearTokens / clearTokenCache ile artar; uçuştaki read/migration
  /// yazıları eski epoch ile cache'i veya secure storage'ı diriltmesin.
  static int _tokenEpoch = 0;

  /// Uzun süren bir iş (token yenileme) başlarken okunur ve [saveTokens]'a
  /// `expectedEpoch` olarak geçirilir: arada çıkış olduysa yazı düşer.
  static int get tokenEpoch => _tokenEpoch;

  static void clearTokenCache() {
    _tokenEpoch++;
    _cachedAccessToken = null;
  }

  static Future<String?> getAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;

    final epoch = _tokenEpoch;

    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyAccessToken);
    if (epoch != _tokenEpoch) return _cachedAccessToken;
    if (token != null) {
      _cachedAccessToken = token;
      return token;
    }

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _tokenEpoch) return _cachedAccessToken;
    token = prefs.getString(_keyAccessToken);
    if (token != null) {
      await _secureStorage.write(key: _keyAccessToken, value: token);
      await prefs.remove(_keyAccessToken);
      if (epoch != _tokenEpoch) {
        // clearTokens yarışı kazandı — migration yazısını geri al.
        await _secureStorage.delete(key: _keyAccessToken);
        return null;
      }
      _cachedAccessToken = token;
    }
    return token;
  }

  /// [expectedEpoch] verilirse (token yenileme yolu) yazı yalnızca o epoch hâlâ
  /// güncelken uygulanır; arada çıkış istendiyse oturum diriltilmez. Giriş
  /// akışı epoch geçirmez: yeni oturumu koşulsuz yazar.
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    int? expectedEpoch,
  }) async {
    final epoch = expectedEpoch ?? _tokenEpoch;
    // Yazının kaynağı araya giren bir çıkıştan ÖNCE başladıysa hiç yazma:
    // clearTokens epoch'u senkron artırdığı için, yazı anında yakalanan epoch
    // artık geçerli görünüyor ve aşağıdaki geri-alma kontrolü tetiklenmiyordu.
    if (epoch != _tokenEpoch) return;
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    if (epoch != _tokenEpoch) {
      // clearTokens uçuş sırasında çağrıldı; yazdıklarımızı sil.
      await _secureStorage.delete(key: _keyAccessToken);
      await _secureStorage.delete(key: _keyRefreshToken);
      return;
    }
    _cachedAccessToken = accessToken;
  }

  static Future<String?> getRefreshToken() async {
    final epoch = _tokenEpoch;
    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyRefreshToken);
    if (epoch != _tokenEpoch) return null;
    if (token != null) return token;

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _tokenEpoch) return null;
    token = prefs.getString(_keyRefreshToken);
    if (token != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: token);
      await prefs.remove(_keyRefreshToken);
      if (epoch != _tokenEpoch) {
        await _secureStorage.delete(key: _keyRefreshToken);
        return null;
      }
    }
    return token;
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUserData);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserData, jsonEncode(userData));
  }

  static Future<String?> getLastAuthenticatedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastAuthenticatedUserId);
  }

  static Future<void> setLastAuthenticatedUserId(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(_keyLastAuthenticatedUserId);
    } else {
      await prefs.setString(_keyLastAuthenticatedUserId, userId);
    }
  }

  static Future<void> clearTokens() async {
    // Epoch senkron artar: uçuştaki okumalar/yazılar hemen terk etsin.
    _tokenEpoch++;
    _cachedAccessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
    _cachedAccessToken = null;
  }

  static Future<void> deleteAllSecure() => _secureStorage.deleteAll();
}
