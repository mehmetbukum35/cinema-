import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';

void main() {
  test('round-trips cultural preferences without neutral entries', () {
    final value = CulturalPreferences.fromJson(
      const CulturalPreferences(
        levels: {
          'korean': CulturePreferenceLevel.prefer,
          'iranian': CulturePreferenceLevel.explore,
          'hollywood': CulturePreferenceLevel.neutral,
        },
        updatedAt: 42,
      ).toJson(),
    );

    expect(value.levelFor('korean'), CulturePreferenceLevel.prefer);
    expect(value.levelFor('iranian'), CulturePreferenceLevel.explore);
    expect(value.levelFor('hollywood'), CulturePreferenceLevel.neutral);
    expect(value.updatedAt, 42);
  });

  test('unknown stored values safely become neutral', () {
    final value = CulturalPreferences.fromJson({
      'levels': {'korean': 99},
    });

    expect(value.isEmpty, isTrue);
  });
}
