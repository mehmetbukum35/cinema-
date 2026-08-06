import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/cultural_preference_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
  });

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

  test('clear removes stored cultural preferences', () async {
    await CulturalPreferenceService.save({
      'korean': CulturePreferenceLevel.prefer,
    });
    expect((await CulturalPreferenceService.load()).isEmpty, isFalse);

    await CulturalPreferenceService.clear();
    expect((await CulturalPreferenceService.load()).isEmpty, isTrue);
  });

  test('learnFromRatings ignores private ratings', () async {
    for (var i = 0; i < 6; i++) {
      await PrefsService.saveRating(
        movie: Movie(
          id: i + 1,
          title: 'Private Korean $i',
          overview: '',
          voteAverage: 8,
          originalLanguage: 'ko',
        ),
        rating: 3,
        isPrivate: 1,

        metadataLocale: 'tr',
      );
    }

    final prefs = await CulturalPreferenceService.load();
    expect(prefs.isEmpty, isTrue);
    expect(prefs.levelFor('korean'), CulturePreferenceLevel.neutral);
  });
}
