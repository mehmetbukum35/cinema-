import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';
import 'package:ne_izlesem/services/cultural_preference_learner.dart';

void main() {
  group('CulturalPreferenceLearner', () {
    test('returns null when classified likes are too few', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(),
        classifiedRatings: [
          (cultures: {'korean'}, rating: 3),
          (cultures: {'korean'}, rating: 3),
          (cultures: {'korean'}, rating: 2),
        ],
      );
      expect(result, isNull);
    });

    test('promotes strong liked culture to prefer', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(),
        classifiedRatings: [
          for (var i = 0; i < 5; i++) (cultures: {'korean'}, rating: 3),
          (cultures: {'korean'}, rating: 1),
        ],
        nowMs: 1000,
      );
      expect(result, isNotNull);
      expect(result!.levelFor('korean'), CulturePreferenceLevel.prefer);
      expect(result.source, 'behavior');
      expect(result.updatedAt, 1000);
    });

    test('upgrades avoid into prefer after consistent likes', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(
          levels: {'turkish': CulturePreferenceLevel.avoid},
        ),
        classifiedRatings: [
          for (var i = 0; i < 5; i++) (cultures: {'turkish'}, rating: 3),
          (cultures: {'turkish'}, rating: 2),
        ],
      );
      expect(result!.levelFor('turkish'), CulturePreferenceLevel.prefer);
    });

    test('soft-downgrades prefer after consistent dislikes', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(
          levels: {'hollywood': CulturePreferenceLevel.prefer},
        ),
        classifiedRatings: [
          for (var i = 0; i < 5; i++) (cultures: {'korean'}, rating: 3),
          (cultures: {'hollywood'}, rating: 0),
          (cultures: {'hollywood'}, rating: 0),
          (cultures: {'hollywood'}, rating: 1),
          (cultures: {'hollywood'}, rating: 2),
        ],
      );
      expect(result!.levelFor('hollywood'), CulturePreferenceLevel.explore);
    });

    test('never invents avoid from behavior alone', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(),
        classifiedRatings: [
          for (var i = 0; i < 5; i++) (cultures: {'korean'}, rating: 3),
          (cultures: {'indian'}, rating: 0),
          (cultures: {'indian'}, rating: 0),
          (cultures: {'indian'}, rating: 1),
        ],
      );
      expect(result?.levelFor('indian'), CulturePreferenceLevel.neutral);
    });

    test('does not overwrite explicit_edit preferences', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(
          levels: {'korean': CulturePreferenceLevel.avoid},
          source: 'explicit_edit',
        ),
        classifiedRatings: [
          for (var i = 0; i < 6; i++) (cultures: {'korean'}, rating: 3),
        ],
      );
      expect(result, isNull);
    });

    test('does not heal dismiss_feedback avoids', () {
      final result = CulturalPreferenceLearner.suggest(
        current: const CulturalPreferences(
          levels: {'turkish': CulturePreferenceLevel.avoid},
          source: 'dismiss_feedback',
        ),
        classifiedRatings: [
          for (var i = 0; i < 6; i++) (cultures: {'turkish'}, rating: 3),
        ],
      );
      expect(result, isNull);
    });
  });
}
