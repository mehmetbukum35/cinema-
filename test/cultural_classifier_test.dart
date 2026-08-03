import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/cultural_classifier.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';

Movie movie({String? language, List<String> countries = const []}) => Movie(
  id: 1,
  title: 'Test',
  overview: '',
  voteAverage: 7,
  originalLanguage: language,
  originCountries: countries,
);

void main() {
  group('CulturalClassifier', () {
    test('classifies Korean cinema by language when country is absent', () {
      expect(CulturalClassifier.classify(movie(language: 'ko')), {'korean'});
    });

    test('keeps co-productions in multiple cultural groups', () {
      expect(
        CulturalClassifier.classify(
          movie(language: 'en', countries: const ['US', 'FR']),
        ),
        containsAll({'hollywood', 'european'}),
      );
    });

    test('does not guess a culture without evidence', () {
      expect(CulturalClassifier.classify(movie()), isEmpty);
    });

    test('maps AU/CA/NZ English-speaking cinema to hollywood', () {
      expect(CulturalClassifier.classify(movie(countries: const ['AU'])), {
        'hollywood',
      });
      expect(CulturalClassifier.classify(movie(countries: const ['CA'])), {
        'hollywood',
      });
      expect(CulturalClassifier.classify(movie(countries: const ['NZ'])), {
        'hollywood',
      });
    });

    test('keeps British cinema in the european bucket', () {
      expect(
        CulturalClassifier.classify(
          movie(language: 'en', countries: const ['GB']),
        ),
        {'european'},
      );
    });
  });

  group('RecommendationEngine cultural scoring', () {
    const preferences = CulturalPreferences(
      levels: {
        'korean': CulturePreferenceLevel.prefer,
        'hollywood': CulturePreferenceLevel.avoid,
      },
    );

    test('boosts preferred cinema and lowers avoided cinema', () {
      final korean = RecommendationEngine.culturalBoost(
        movie: movie(language: 'ko'),
        preferences: preferences,
        ratingCount: 0,
      );
      final hollywood = RecommendationEngine.culturalBoost(
        movie: movie(language: 'en', countries: const ['US']),
        preferences: preferences,
        ratingCount: 0,
      );

      expect(korean, 0.10);
      expect(hollywood, -0.12);
    });

    test('reduces onboarding influence as real ratings accumulate', () {
      expect(RecommendationEngine.culturalPreferenceInfluence(0), 1);
      expect(RecommendationEngine.culturalPreferenceInfluence(10), 0.6);
      expect(RecommendationEngine.culturalPreferenceInfluence(25), 0.3);
      expect(RecommendationEngine.culturalPreferenceInfluence(50), 0.15);
    });

    test('never applies a cultural score without classification evidence', () {
      expect(
        RecommendationEngine.culturalBoost(
          movie: movie(),
          preferences: preferences,
          ratingCount: 0,
        ),
        0,
      );
    });
  });
}
