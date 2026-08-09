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

  static void clearTokenCache() {
    _cachedAccessToken = null;
  }

  static Future<String?> getAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;

    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyAccessToken);
    if (token != null) {
      _cachedAccessToken = token;
      return token;
    }

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyAccessToken);
    if (token != null) {
      await _secureStorage.write(key: _keyAccessToken, value: token);
      await prefs.remove(_keyAccessToken);
      _cachedAccessToken = token;
    }
    return token;
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    _cachedAccessToken = accessToken;
  }

  static Future<String?> getRefreshToken() async {
    // Try secure storage first
    String? token = await _secureStorage.read(key: _keyRefreshToken);
    if (token != null) return token;

    // Migration fallback
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyRefreshToken);
    if (token != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: token);
      await prefs.remove(_keyRefreshToken);
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
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = null;
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
  }
}
