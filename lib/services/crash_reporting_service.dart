import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Central crash reporting entry point.
///
/// Crash collection is disabled for debug builds and unsupported platforms.
/// Callers never have to guard reporting: failures in telemetry must not affect
/// the application itself.
class CrashReportingService {
  CrashReportingService._();

  static bool _ready = false;

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> initialize() async {
    if (!_isSupported) return;

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      _ready = true;
    } catch (error) {
      debugPrint('Crash reporting initialization failed: $error');
    }
  }

  static Future<void> record(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  }) async {
    if (!_ready || kDebugMode) return;

    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
        reason: reason,
      );
    } catch (_) {
      // Telemetry is best-effort and must never create another app failure.
    }
  }
}
