import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_service.dart';

enum RecommendationExperimentVariant { control, personalization }

class RecommendationExperiment {
  final RecommendationExperimentVariant variant;
  final String modelVersion;
  final ({double genre, double vote}) genreOnlyWeights;
  final ({double genre, double keyword, double vote}) fullWeights;
  final double preferenceBoostMultiplier;

  const RecommendationExperiment({
    required this.variant,
    required this.modelVersion,
    required this.genreOnlyWeights,
    required this.fullWeights,
    required this.preferenceBoostMultiplier,
  });

  bool get isPersonalization =>
      variant == RecommendationExperimentVariant.personalization;
}

class RecommendationExperimentService {
  static const experimentId = 'ranking_weights_v2';
  static const _key = 'recommendation_experiment_$experimentId';

  static const control = RecommendationExperiment(
    variant: RecommendationExperimentVariant.control,
    modelVersion: 'recommendation_v5_ab_control',
    genreOnlyWeights: (genre: 0.70, vote: 0.30),
    fullWeights: (genre: 0.45, keyword: 0.25, vote: 0.30),
    preferenceBoostMultiplier: 1.0,
  );

  static const personalization = RecommendationExperiment(
    variant: RecommendationExperimentVariant.personalization,
    modelVersion: 'recommendation_v5_ab_personalization',
    genreOnlyWeights: (genre: 0.78, vote: 0.22),
    fullWeights: (genre: 0.50, keyword: 0.30, vote: 0.20),
    preferenceBoostMultiplier: 1.25,
  );

  static Future<RecommendationExperiment> current() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == RecommendationExperimentVariant.control.name) return control;
    if (stored == RecommendationExperimentVariant.personalization.name) {
      return personalization;
    }

    final deviceId = await PrefsService.getSyncDeviceId();
    final assignment = assignmentFor(deviceId);
    await prefs.setString(_key, assignment.variant.name);
    return assignment;
  }

  static RecommendationExperiment assignmentFor(String stableId) {
    var hash = 0x811c9dc5;
    for (final byte in stableId.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.isEven ? control : personalization;
  }
}
