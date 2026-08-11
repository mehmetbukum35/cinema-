import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Öneri telemetrisi (isabet oranı), dismiss geri bildirimi ve gösterim
/// hafızası (impression cooldown / "Bu Gece" geçmişi). Yalnızca cihazda
/// tutulur.
///
/// Public çağrı yüzeyi hâlâ [PrefsTastePrefs]; bu sınıf taşıma hedefidir.
///
/// Cycle kuralı: bu dosya `prefs_service.dart` import ETMEZ.
class PrefsRecoSignals {
  // ─── Öneri isabet telemetrisi ────────────────────────────────────────────────
  // Kaynak bazında (discover/seed/friend) kaç öneri gösterilip kaçının
  // İyi/Harika aldığını sayar. Motorun gerçek başarısını ölçmenin tek yolu:
  // "önerdik → beğendi mi?" dönüşümü. Yalnızca cihazda tutulur.

  static const _keyRecoTelemetry = 'reco_telemetry_v2';
  static const _keyLegacyRecoTelemetry = 'reco_telemetry_v1';
  static Future<void> _recoTelemetryTail = Future<void>.value();
  static bool _legacyPurged = false;

  static Future<void> _enqueueRecoTelemetry(Future<void> Function() operation) {
    final previous = _recoTelemetryTail;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later telemetry updates.
      }
      await operation();
    }();
    _recoTelemetryTail = current;
    return current;
  }

  static int _asInt(Object? v) =>
      v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  /// Bozuk yük yeni sayaç gibi davranır — telemetri hiçbir zaman akışı kırmaz.
  static Map<String, dynamic> _decodeTelemetry(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  static Map<String, dynamic> _bucketOf(
    Map<String, dynamic> data,
    String source,
  ) {
    final value = data[source];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : {'shown': 0, 'liked': 0};
  }

  /// Gösterim: kaynak başına `shown++`. Atıfsız (`null`) yapımlar elenir —
  /// arama gibi öneri motoru dışı yüzeyler sayaçları kirletmesin.
  static Future<void> recordRecoShown(Iterable<String?> sources) {
    final counted = sources.whereType<String>().toList(growable: false);
    if (counted.isEmpty) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      for (final source in counted) {
        final bucket = _bucketOf(data, source);
        bucket['shown'] = _asInt(bucket['shown']) + 1;
        data[source] = bucket;
      }
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// İsabet: yalnızca İyi/Harika (rating >= 2) oy geldiğinde çağrılır.
  static Future<void> recordRecoLiked(String? source) {
    if (source == null) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      final bucket = _bucketOf(data, source);
      bucket['liked'] = _asInt(bucket['liked']) + 1;
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// Puan silindi: isabeti geri al. `shown`'a DOKUNMAZ — gösterim gerçekten
  /// olmuştu, kullanıcının fikrini değiştirmesi onu geri almaz.
  static Future<void> revertRecoLiked(String? source) {
    if (source == null) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      final bucket = _bucketOf(data, source);
      final liked = _asInt(bucket['liked']);
      if (liked > 0) bucket['liked'] = liked - 1;
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// Kaynak → {shown, liked} sayaçları. Beğeni oranı = liked/shown.
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_legacyPurged) {
      _legacyPurged = true;
      // v1'in paydası "oylandı"ydı; v2'ninki "gösterildi". Karışım her iki
      // oranı da bozar, o yüzden taşınmaz — silinir.
      await prefs.remove(_keyLegacyRecoTelemetry);
    }
    final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
    return data.map(
      (k, v) => MapEntry(
        k,
        v is Map
            ? Map<String, dynamic>.from(
                v,
              ).map((k2, v2) => MapEntry(k2, _asInt(v2)))
            : <String, int>{},
      ),
    );
  }

  static const _keyDismissFeedback = 'dismiss_feedback_v1';
  static const _keyDismissCount = 'dismiss_feedback_count_v1';
  static const _keyDismissLastAsked = 'dismiss_feedback_last_asked_v1';

  static Future<bool> shouldAskDismissFeedback({
    required int matchScore,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_keyDismissCount) ?? 0) + 1;
    await prefs.setInt(_keyDismissCount, count);
    final lastAsked = prefs.getInt(_keyDismissLastAsked) ?? 0;
    final cooldownPassed =
        DateTime.now().millisecondsSinceEpoch - lastAsked >
        const Duration(hours: 24).inMilliseconds;
    final shouldAsk = cooldownPassed && (matchScore >= 75 || count % 4 == 0);
    if (shouldAsk) {
      await prefs.setInt(
        _keyDismissLastAsked,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    return shouldAsk;
  }

  static Future<void> recordDismissFeedback({
    required String movieKey,
    required String reason,
    required String source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDismissFeedback) ?? '[]';
    final decoded = jsonDecode(raw);
    final events = decoded is List
        ? decoded
              .whereType<Map<Object?, Object?>>()
              .map(Map<String, dynamic>.from)
              .toList()
        : <Map<String, dynamic>>[];
    events.add({
      'movie_key': movieKey,
      'reason': reason,
      'source': source,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    if (events.length > 100) events.removeRange(0, events.length - 100);
    await prefs.setString(_keyDismissFeedback, jsonEncode(events));
  }

  static Future<List<Map<String, dynamic>>> getDismissFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString(_keyDismissFeedback) ?? '[]');
    return decoded is List
        ? decoded
              .whereType<Map<Object?, Object?>>()
              .map(Map<String, dynamic>.from)
              .toList()
        : const [];
  }

  // ─── Öneri gösterim hafızası (impression cooldown) ─────────────────────────
  // "Dün gösterdik, etkileşmedi" sinyali: vitrine/raya çıkan yapımlar kısa bir
  // süre skor cezası alır ki her açılışta aynı yüzler dizilmesin. Yalnızca
  // cihazda tutulur; boyut sınırlı, eski kayıtlar kendiliğinden budanır.

  static const _keyRecoImpressions = 'reco_impressions_v1';
  static const _keyTonightHistory = 'tonight_history_v1';

  static Future<Map<String, int>> _getTimestampMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? '{}';
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _recordTimestamps(
    String prefKey,
    List<String> keys, {
    required int maxAgeMs,
    required int maxEntries,
  }) async {
    if (keys.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    var data = await _getTimestampMap(prefKey);
    for (final k in keys) {
      data[k] = now;
    }
    data.removeWhere((_, v) => now - v > maxAgeMs);
    if (data.length > maxEntries) {
      final entries = data.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      data = Map.fromEntries(entries.take(maxEntries));
    }
    await prefs.setString(prefKey, jsonEncode(data));
  }

  /// key → son gösterim (ms). 14 gün pencere, en fazla 400 kayıt.
  static Future<Map<String, int>> getRecoImpressions() =>
      _getTimestampMap(_keyRecoImpressions);

  static Future<void> recordRecoImpressions(List<String> keys) =>
      _recordTimestamps(
        _keyRecoImpressions,
        keys,
        maxAgeMs: 14 * 24 * 3600 * 1000,
        maxEntries: 400,
      );

  /// Vitrin ("Bu Gece Ne İzlesem?") geçmişi: aynı yapım 7 gün içinde tekrar
  /// vitrin olmasın diye ayrı ve daha uzun pencereli tutulur.
  static Future<Map<String, int>> getTonightHistory() =>
      _getTimestampMap(_keyTonightHistory);

  static Future<void> recordTonightPick(String key) => _recordTimestamps(
    _keyTonightHistory,
    [key],
    maxAgeMs: 30 * 24 * 3600 * 1000,
    maxEntries: 60,
  );

  // ─── Bellek içi cache sıfırlama ─────────────────────────────────────────────

  static void resetInMemoryCaches() {
    _recoTelemetryTail = Future<void>.value();
    _legacyPurged = false;
  }
}
