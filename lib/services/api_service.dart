import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/social.dart';
import 'app_config.dart';
import 'crash_reporting_service.dart';
import 'prefs/auth_storage.dart';
import 'prefs/sync_meta.dart';
import 'prefs_service.dart';

part 'api/auth_api.dart';
part 'api/client.dart';
part 'api/couch_api.dart';
part 'api/recommendation_api.dart';
part 'api/social_api.dart';
part 'api/sync_api.dart';

/// Backwards-compatible facade over focused domain APIs.
class ApiService extends ApiClient
    with AuthApi, SyncApi, SocialApi, RecommendationApi, CouchApi {
  ApiService({
    super.client,
    super.onSessionExpired,
    super.requestTimeout,
    super.transientRetryDelay,
    super.localeCode,
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

  factory ApiException.fromData(
    Map<String, dynamic> data, {
    required int statusCode,
    required String fallbackMessage,
  }) {
    final rawError = data['error'];
    String message = fallbackMessage;
    if (rawError is String && rawError.trim().isNotEmpty) {
      message = rawError.trim();
    } else if (rawError is Map) {
      final msg = rawError['message'] ?? rawError['error'];
      if (msg != null && msg.toString().trim().isNotEmpty) {
        message = msg.toString().trim();
      }
    } else if (rawError != null) {
      final str = rawError.toString().trim();
      if (str.isNotEmpty) message = str;
    }

    final rawCode = data['code'];
    final code = rawCode?.toString();

    return ApiException(statusCode: statusCode, message: message, code: code);
  }

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}
