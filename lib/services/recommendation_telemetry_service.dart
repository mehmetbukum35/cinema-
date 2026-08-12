import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/movie.dart';
import 'recommendation_experiment_service.dart';

class RecommendationTelemetryService {
  /// Son çare: atıfsız bir olayın taşıyacağı sürüm. Aktif yapılandırmadan
  /// türetilir ki elle yazılmış bir sabit bir daha bayatlamasın.
  static String get modelVersion =>
      RecommendationExperimentService.active.modelVersion;
  static const _queueKey = 'recommendation_event_queue_v1';
  static const _latestKey = 'recommendation_latest_impressions_v1';
  static const _uuid = Uuid();
  static Future<void> _writeTail = Future<void>.value();

  /// Tek sıralama geçişinin birden çok slot'a yayılan gösterimlerini bağlamak
  /// için (ör. Keşfet'te vitrin kartı + sıralı liste).
  static String newBatchId() => _uuid.v4();

  static String movieKey(Movie movie) =>
      '${movie.isTV ? 'tv' : 'movie'}_${movie.id}';

  /// [slot] gösterim yuvası: `list` (sıralı liste), `tonight` (vitrin/hero
  /// kartı), `card` (swipe). Hero kartı listenin ilk elemanı DEĞİL — ayrı
  /// etiketlenmezse kalibrasyon slot etkisini zevk sinyali sanır.
  ///
  /// [batchId] tek bir sıralama geçişinden çıkan tüm gösterimleri birbirine
  /// bağlar; verilmezse üretilir. Sıralanmış listenin tamamını yeniden kurmak
  /// (ters-olasılık ağırlığı, listwise değerlendirme) buna bağlı.
  ///
  /// Not: gösterim listeyi KURARKEN yazılıyor, viewport'a girince değil. Yani
  /// `rank` incelenme olasılığının ölçümü değil vekili — pozisyon-yanlılığı
  /// düzeltmesi bunu varsayım olarak almalı. Tek istisna `card` (swipe):
  /// kullanıcı her kartı görüp aksiyon almak zorunda, o yüzden o yüzeyde
  /// gösterim yanlılığı yok.
  static Future<void> recordShown(
    Iterable<Movie> movies, {
    required String surface,
    String slot = 'list',
    String? batchId,
  }) => _enqueue(() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readList(prefs.getString(_queueKey));
    final latest = _readMap(prefs.getString(_latestKey));
    final now = DateTime.now().millisecondsSinceEpoch;
    final resolvedBatchId = batchId ?? _uuid.v4();
    var rank = 0;
    final experiment = RecommendationExperimentService.active;

    for (final movie in movies) {
      final impressionId = _uuid.v4();
      final assignedModelVersion =
          movie.recommendationModelVersion ?? experiment.modelVersion;
      movie
        ..recommendationImpressionId = impressionId
        ..recommendationModelVersion = assignedModelVersion;
      latest[movieKey(movie)] = {
        'impression_id': impressionId,
        'model_version': assignedModelVersion,
        'shown_at': now,
      };
      queue.add(
        _event(
          movie: movie,
          impressionId: impressionId,
          action: 'shown',
          surface: surface,
          createdAt: now,
          metadata: {'rank': rank, 'slot': slot, 'batch_id': resolvedBatchId},
        ),
      );
      rank++;
    }
    await _persist(prefs, queue, latest);
  });

  static Future<void> recordAction(
    Movie movie, {
    required String action,
    required String surface,
    Map<String, dynamic> metadata = const {},
  }) => _enqueue(() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readList(prefs.getString(_queueKey));
    final latest = _readMap(prefs.getString(_latestKey));
    final latestForMovie = latest[movieKey(movie)];
    final impressionId =
        movie.recommendationImpressionId ??
        (latestForMovie is Map
            ? latestForMovie['impression_id']?.toString()
            : null);
    if (impressionId == null) return;
    final attributedModelVersion =
        movie.recommendationModelVersion ??
        (latestForMovie is Map
            ? latestForMovie['model_version']?.toString()
            : null);
    queue.add(
      _event(
        movie: movie,
        impressionId: impressionId,
        action: action,
        surface: surface,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        metadata: metadata,
        eventModelVersion: attributedModelVersion,
      ),
    );
    await _persist(prefs, queue, latest);
  });

  static Future<List<Map<String, dynamic>>> pendingEvents() async {
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs.getString(_queueKey));
  }

  static Future<void> removeEvents(Set<String> eventIds) async {
    if (eventIds.isEmpty) return;
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final queue = _readList(prefs.getString(_queueKey))
        ..removeWhere((event) => eventIds.contains(event['event_id']));
      await prefs.setString(_queueKey, jsonEncode(queue));
    });
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _writeTail;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // Bir telemetri yazımı sonraki olayları kalıcı olarak engellememeli.
      }
      await operation();
    }();
    _writeTail = current;
    return current;
  }

  static Map<String, dynamic> _event({
    required Movie movie,
    required String impressionId,
    required String action,
    required String surface,
    required int createdAt,
    Map<String, dynamic> metadata = const {},
    String? eventModelVersion,
  }) => {
    'event_id': _uuid.v4(),
    'impression_id': impressionId,
    'movie_id': movie.id,
    'is_tv': movie.isTV,
    'action': action,
    'surface': surface,
    'source': movie.recoSource ?? 'unknown',
    'model_version':
        eventModelVersion ??
        movie.recommendationModelVersion ??
        RecommendationTelemetryService.modelVersion,
    'score_components': movie.recommendationScoreComponents,
    'metadata': metadata,
    'created_at': createdAt,
  };

  static List<Map<String, dynamic>> _readList(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<Object?, Object?>>()
            .map(Map<String, dynamic>.from)
            .toList();
      }
    } on FormatException {
      // Bozuk telemetri kuyruğu yeni kuyruk gibi davranır.
    }
    return [];
  }

  static Map<String, dynamic> _readMap(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Bozuk son gösterim indeksi yeniden oluşturulur.
    }
    return {};
  }

  static Future<void> _persist(
    SharedPreferences prefs,
    List<Map<String, dynamic>> queue,
    Map<String, dynamic> latest,
  ) async {
    if (queue.length > 500) queue.removeRange(0, queue.length - 500);
    await Future.wait([
      prefs.setString(_queueKey, jsonEncode(queue)),
      prefs.setString(_latestKey, jsonEncode(latest)),
    ]);
  }
}
