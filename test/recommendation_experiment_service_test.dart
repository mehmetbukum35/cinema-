import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';
import 'package:ne_izlesem/services/recommendation_experiment_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('assignment is stable for the same installation id', () {
    final first = RecommendationExperimentService.assignmentFor('device-123');
    final second = RecommendationExperimentService.assignmentFor('device-123');

    expect(second.variant, first.variant);
    expect(second.modelVersion, first.modelVersion);
  });

  test('experiment variants use distinct model versions and weights', () {
    expect(
      RecommendationExperimentService.control.modelVersion,
      isNot(RecommendationExperimentService.personalization.modelVersion),
    );
    expect(
      RecommendationExperimentService.personalization.fullWeights.keyword,
      greaterThan(RecommendationExperimentService.control.fullWeights.keyword),
    );
    expect(
      RecommendationExperimentService.personalization.preferenceBoostMultiplier,
      greaterThan(1),
    );
  });

  test('personalization variant gives preference signals more weight', () {
    final control = RecommendationEngine.blend(
      genreSim: 1,
      kwSim: 1,
      voteAverage: 0,
      experiment: RecommendationExperimentService.control,
    );
    final treatment = RecommendationEngine.blend(
      genreSim: 1,
      kwSim: 1,
      voteAverage: 0,
      experiment: RecommendationExperimentService.personalization,
    );

    expect(treatment, greaterThan(control));
  });

  test('current assignment persists across reads', () async {
    final first = await RecommendationExperimentService.current();
    final second = await RecommendationExperimentService.current();

    expect(second.variant, first.variant);
  });
}
