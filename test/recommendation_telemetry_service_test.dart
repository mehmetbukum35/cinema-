import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_experiment_service.dart';
import 'package:ne_izlesem/services/recommendation_telemetry_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'recommendation_experiment_ranking_weights_v2': 'control',
    });
  });

  test('links actions to the latest shown impression', () async {
    final movie = Movie(
      id: 550,
      title: 'Fight Club',
      overview: '',
      voteAverage: 8.4,
    )..recoSource = 'culture';

    await RecommendationTelemetryService.recordShown([
      movie,
    ], surface: 'browse');
    await RecommendationTelemetryService.recordAction(
      movie,
      action: 'detail_opened',
      surface: 'browse',
    );

    final events = await RecommendationTelemetryService.pendingEvents();
    expect(events, hasLength(2));
    expect(events[0]['action'], 'shown');
    expect(events[1]['action'], 'detail_opened');
    expect(events[1]['impression_id'], events[0]['impression_id']);
    expect(
      events[0]['model_version'],
      RecommendationExperimentService.active.modelVersion,
    );
  });

  test('ignores actions that have no recommendation impression', () async {
    final movie = Movie(
      id: 1,
      title: 'Search result',
      overview: '',
      voteAverage: 7,
    );

    await RecommendationTelemetryService.recordAction(
      movie,
      action: 'detail_opened',
      surface: 'search',
    );

    expect(await RecommendationTelemetryService.pendingEvents(), isEmpty);
  });

  test('actions from a movie copy keep the shown experiment model', () async {
    final shown = Movie(id: 9, title: 'Shown', overview: '', voteAverage: 7)
      ..recommendationModelVersion = 'recommendation_v5_ab_personalization';
    final detailCopy = Movie(
      id: 9,
      title: 'Shown',
      overview: '',
      voteAverage: 7,
    );

    await RecommendationTelemetryService.recordShown([
      shown,
    ], surface: 'browse');
    await RecommendationTelemetryService.recordAction(
      detailCopy,
      action: 'trailer_opened',
      surface: 'movie_detail',
    );

    final events = await RecommendationTelemetryService.pendingEvents();
    expect(events[1]['impression_id'], events[0]['impression_id']);
    expect(events[1]['model_version'], 'recommendation_v5_ab_personalization');
  });

  test('removes acknowledged events idempotently', () async {
    final movie = Movie(id: 2, title: 'Test', overview: '', voteAverage: 7);
    await RecommendationTelemetryService.recordShown([
      movie,
    ], surface: 'browse');
    final events = await RecommendationTelemetryService.pendingEvents();
    final id = events.single['event_id'] as String;

    await RecommendationTelemetryService.removeEvents({id});
    await RecommendationTelemetryService.removeEvents({id});

    expect(await RecommendationTelemetryService.pendingEvents(), isEmpty);
  });

  test('records swipe rating metadata and trailer conversion', () async {
    final movie = Movie(id: 3, title: 'Test', overview: '', voteAverage: 7);
    await RecommendationTelemetryService.recordShown([movie], surface: 'swipe');
    await RecommendationTelemetryService.recordAction(
      movie,
      action: 'rated',
      surface: 'swipe',
      metadata: {'rating': 3, 'interaction': 'gesture'},
    );
    await RecommendationTelemetryService.recordAction(
      movie,
      action: 'trailer_opened',
      surface: 'movie_detail',
    );

    final events = await RecommendationTelemetryService.pendingEvents();
    expect(events.map((event) => event['action']), [
      'shown',
      'rated',
      'trailer_opened',
    ]);
    expect(events[1]['metadata'], {'rating': 3, 'interaction': 'gesture'});
    expect(events.map((event) => event['impression_id']).toSet(), hasLength(1));
  });

  // Kuyruk 500'de kesiliyor ama son-gösterim indeksi büdanmazsa sınırsız
  // büyür ve HER telemetri yazımında baştan encode edilir.
  test('son gösterim indeksi sınırsız büyümez, en yeniyi tutar', () async {
    Movie m(int id) =>
        Movie(id: id, title: 'M$id', overview: '', voteAverage: 7);

    await RecommendationTelemetryService.recordShown([
      for (var id = 1; id <= 320; id++) m(id),
    ], surface: 'browse');

    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> latest() =>
        jsonDecode(
              prefs.getString('recommendation_latest_impressions_v1') ?? '{}',
            )
            as Map<String, dynamic>;

    expect(latest(), hasLength(300));
    expect(latest().containsKey('movie_1'), isFalse);
    expect(latest().containsKey('movie_320'), isTrue);

    // Yeniden gösterilen yapım en tazeye taşınır; budama en eskiden başlar.
    // m(321) sınırı aştırır, m(21) tazelendiği için kurban m(22) olur.
    await RecommendationTelemetryService.recordShown([
      m(21),
      m(321),
    ], surface: 'browse');

    expect(latest(), hasLength(300));
    expect(latest().containsKey('movie_21'), isTrue);
    expect(latest().containsKey('movie_22'), isFalse);
  });
}
