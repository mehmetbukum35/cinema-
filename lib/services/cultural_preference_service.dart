import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cultural_preferences.dart';

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
}
