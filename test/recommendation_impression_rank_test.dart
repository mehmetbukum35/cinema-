import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_telemetry_service.dart';

/// Sıralama kalibrasyonunun kapısı: gösterim olayı hangi sırada, hangi yuvada
/// ve hangi sıralama geçişinde olduğunu taşımazsa, toplanan score_components
/// pozisyon yanlılığından ayrıştırılamaz — ve bu alanlar geriye dönük
/// doldurulamaz. Bkz. recordShown dokümantasyonu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Movie movie(int id) =>
      Movie(id: id, title: 'M$id', overview: '', voteAverage: 7.0);

  Future<List<Map<String, dynamic>>> shownEvents() async {
    final events = await RecommendationTelemetryService.pendingEvents();
    return [
      for (final e in events)
        if (e['action'] == 'shown') e,
    ];
  }

  Map<String, dynamic> metaOf(Map<String, dynamic> event) {
    final raw = event['metadata'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
  }

  test('impressions carry their rank in surface order', () async {
    await RecommendationTelemetryService.recordShown([
      movie(1),
      movie(2),
      movie(3),
    ], surface: 'browse');

    final events = await shownEvents();
    expect(events, hasLength(3));
    expect(
      [for (final e in events) metaOf(e)['rank']],
      [0, 1, 2],
      reason: 'sıra kaydedilmezse pozisyon yanlılığı düzeltilemez',
    );
  });

  test('the hero card is a slot of its own, not list position zero', () async {
    final batchId = RecommendationTelemetryService.newBatchId();
    await RecommendationTelemetryService.recordShown(
      [movie(1)],
      surface: 'browse',
      slot: 'tonight',
      batchId: batchId,
    );
    await RecommendationTelemetryService.recordShown(
      [movie(2), movie(3)],
      surface: 'browse',
      slot: 'list',
      batchId: batchId,
    );

    final events = await shownEvents();
    final metas = [for (final e in events) metaOf(e)];

    expect(metas.map((m) => m['slot']), ['tonight', 'list', 'list']);
    expect(
      metas.map((m) => m['batch_id']).toSet(),
      {batchId},
      reason: 'tek sıralama geçişi tek batch_id ile yeniden kurulabilmeli',
    );
  });

  test('separate ranking passes do not share a batch id', () async {
    await RecommendationTelemetryService.recordShown(
      [movie(1)],
      surface: 'swipe',
      slot: 'card',
    );
    await RecommendationTelemetryService.recordShown(
      [movie(2)],
      surface: 'swipe',
      slot: 'card',
    );

    final metas = [for (final e in await shownEvents()) metaOf(e)];
    expect(metas.map((m) => m['batch_id']).toSet(), hasLength(2));
    expect(metas.map((m) => m['slot']), ['card', 'card']);
  });
}
