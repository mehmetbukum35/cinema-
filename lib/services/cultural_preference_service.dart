import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cultural_preferences.dart';
import '../models/movie.dart';
import 'cultural_classifier.dart';
import 'cultural_preference_learner.dart';
import 'db_helper.dart';

class CulturalPreferenceService {
  static const storageKey = 'cultural_preferences_v1';

  static Future<CulturalPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const CulturalPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CulturalPreferences.fromJson(decoded);
      }
    } on FormatException {
      // Bozuk tercih verisi cevaplanmamış onboarding gibi davranır.
    }
    return const CulturalPreferences();
  }

  static Future<void> save(
    Map<String, CulturePreferenceLevel> levels, {
    String source = 'onboarding',
  }) async {
    final normalized = Map<String, CulturePreferenceLevel>.fromEntries(
      levels.entries.where(
        (entry) => entry.value != CulturePreferenceLevel.neutral,
      ),
    );
    final value = CulturalPreferences(
      levels: normalized,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      source: source,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(value.toJson()));
  }

  static Future<void> saveSnapshot(CulturalPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(value.toJson()));
  }

  /// Hesap değişimi / yerel wipe sonrası cihazdaki kültür tercihlerini siler.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  /// Puanlamalardan kültürel tercihleri yumuşak günceller. Değişiklik olduysa true.
  static Future<bool> learnFromRatings() async {
    final current = await load();
    final raw = await DatabaseHelper().getRatings();
    final classified = <({Set<String> cultures, int rating})>[];
    for (final row in raw) {
      // Özel puanlar DNA / yayınlanan kültür sinyalini şekillendirmesin.
      if ((row['is_private'] as int? ?? 0) == 1) continue;
      final movie = row['movie'];
      if (movie is! Movie) continue;
      final cultures = CulturalClassifier.classify(movie);
      if (cultures.isEmpty) continue;
      final rating = row['rating'];
      final ratingInt = rating is int
          ? rating
          : int.tryParse(rating?.toString() ?? '') ?? -1;
      classified.add((cultures: cultures, rating: ratingInt));
    }
    final suggested = CulturalPreferenceLearner.suggest(
      current: current,
      classifiedRatings: classified,
    );
    if (suggested == null) return false;
    await saveSnapshot(suggested);
    return true;
  }
}
