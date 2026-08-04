import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cultural_preferences.dart';
import 'package:ne_izlesem/models/discovery_context.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/recommendation_engine.dart';

Movie title({
  bool isTV = false,
  String? language,
  List<String> countries = const [],
  int? runtime,
  double popularity = 50,
  int voteCount = 500,
  double voteAverage = 7,
}) => Movie(
  id: 1,
  title: 'Test',
  overview: '',
  voteAverage: voteAverage,
  isTV: isTV,
  originalLanguage: language,
  originCountries: countries,
  runtimeMinutes: runtime,
  popularity: popularity,
  voteCount: voteCount,
);

void main() {
  group('resolveHomeCultures', () {
    test('falls back to Turkish for tr locale without prefers', () {
      expect(
        RecommendationEngine.resolveHomeCultures(
          preferences: const CulturalPreferences(),
          languageCode: 'tr',
        ),
        {'turkish'},
      );
    });

    test('falls back to Hollywood for en locale without prefers', () {
      expect(
        RecommendationEngine.resolveHomeCultures(
          preferences: const CulturalPreferences(),
          languageCode: 'en',
        ),
        {'hollywood'},
      );
    });

    test('prefers declared cultural preferences over app language', () {
      expect(
        RecommendationEngine.resolveHomeCultures(
          preferences: const CulturalPreferences(
            levels: {
              'korean': CulturePreferenceLevel.prefer,
              'european': CulturePreferenceLevel.explore,
            },
          ),
          languageCode: 'tr',
        ),
        {'korean'},
      );
    });
  });

  group('Discovery context filtering', () {
    test('movie and TV choices filter the opposite media type', () {
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(),
          const DiscoveryContext(media: DiscoveryMedia.movie),
        ),
        isTrue,
      );
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(isTV: true),
          const DiscoveryContext(media: DiscoveryMedia.movie),
        ),
        isFalse,
      );
    });

    test('local/foreign follow the resolved home cultures', () {
      const home = {'hollywood'};
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'en', countries: const ['US']),
          const DiscoveryContext(origin: DiscoveryOrigin.local),
          homeCultures: home,
        ),
        isTrue,
      );
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'tr'),
          const DiscoveryContext(origin: DiscoveryOrigin.local),
          homeCultures: home,
        ),
        isFalse,
      );
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'tr'),
          const DiscoveryContext(origin: DiscoveryOrigin.foreign),
          homeCultures: home,
        ),
        isTrue,
      );
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'en', countries: const ['US']),
          const DiscoveryContext(origin: DiscoveryOrigin.foreign),
          homeCultures: home,
        ),
        isFalse,
      );
    });

    test('Turkish home still treats Turkish cinema as local', () {
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'tr'),
          const DiscoveryContext(origin: DiscoveryOrigin.local),
          homeCultures: const {'turkish'},
        ),
        isTrue,
      );
      expect(
        RecommendationEngine.matchesDiscoveryContext(
          title(language: 'ko'),
          const DiscoveryContext(origin: DiscoveryOrigin.local),
          homeCultures: const {'turkish'},
        ),
        isFalse,
      );
    });
  });

  group('Discovery context scoring', () {
    test('duration only affects titles with runtime evidence', () {
      const context = DiscoveryContext(duration: DiscoveryDuration.short);
      expect(
        RecommendationEngine.discoveryContextBoost(title(runtime: 90), context),
        0.08,
      );
      expect(
        RecommendationEngine.discoveryContextBoost(
          title(runtime: 150),
          context,
        ),
        -0.10,
      );
      expect(RecommendationEngine.discoveryContextBoost(title(), context), 0);
    });

    test('safe mode favors established highly rated titles', () {
      const context = DiscoveryContext(familiarity: DiscoveryFamiliarity.safe);
      final established = RecommendationEngine.discoveryContextBoost(
        title(voteAverage: 8, voteCount: 5000),
        context,
      );
      final obscure = RecommendationEngine.discoveryContextBoost(
        title(voteAverage: 6, voteCount: 50),
        context,
      );
      expect(established, greaterThan(obscure));
    });

    test('surprise mode favors lower-popularity candidates', () {
      const context = DiscoveryContext(
        familiarity: DiscoveryFamiliarity.surprise,
      );
      final obscure = RecommendationEngine.discoveryContextBoost(
        title(popularity: 20, voteCount: 100),
        context,
      );
      final mainstream = RecommendationEngine.discoveryContextBoost(
        title(popularity: 200, voteCount: 5000),
        context,
      );
      expect(obscure, greaterThan(mainstream));
    });
  });
}
