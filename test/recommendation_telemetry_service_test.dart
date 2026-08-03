import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_telemetry_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    expect(events[0]['model_version'], 'recommendation_v4_ab_control');
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
}
