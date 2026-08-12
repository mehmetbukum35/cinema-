import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';
import 'package:ne_izlesem/services/recommendation_experiment_service.dart';
import 'package:ne_izlesem/services/recommendation_telemetry_service.dart';

void main() {
  test('aktif yapılandırma tercih sinyallerine ağırlık verir', () {
    const active = RecommendationExperimentService.active;

    // Tür lider, keyword güçlü ikinci, TMDB puanı taban.
    expect(active.fullWeights.genre, greaterThan(active.fullWeights.keyword));
    expect(active.fullWeights.keyword, greaterThan(active.fullWeights.vote));
    expect(active.preferenceBoostMultiplier, greaterThan(1));
  });

  test('harman ağırlıkları 1.0 toplar', () {
    const active = RecommendationExperimentService.active;

    expect(
      active.genreOnlyWeights.genre + active.genreOnlyWeights.vote,
      closeTo(1.0, 1e-9),
    );
    expect(
      active.fullWeights.genre +
          active.fullWeights.keyword +
          active.fullWeights.vote,
      closeTo(1.0, 1e-9),
    );
  });

  test('blend varsayılan olarak aktif yapılandırmayı kullanır', () {
    final withDefault = RecommendationEngine.blend(
      genreSim: 0.5,
      kwSim: 0.5,
      voteAverage: 7,
    );
    final explicit = RecommendationEngine.blend(
      genreSim: 0.5,
      kwSim: 0.5,
      voteAverage: 7,
      experiment: RecommendationExperimentService.active,
    );

    expect(withDefault, explicit);
  });

  test('telemetri son çare sürümü aktif yapılandırmadan türer', () {
    // Elle yazılmış bir sabit bayatlayıp olayları yanlış sürümle etiketlemesin.
    expect(
      RecommendationTelemetryService.modelVersion,
      RecommendationExperimentService.active.modelVersion,
    );
  });
}
