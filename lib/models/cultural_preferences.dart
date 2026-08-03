enum CulturePreferenceLevel {
  avoid(-1),
  neutral(0),
  explore(1),
  prefer(2);

  const CulturePreferenceLevel(this.value);
  final int value;

  static CulturePreferenceLevel fromValue(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return CulturePreferenceLevel.values.firstWhere(
      (level) => level.value == parsed,
      orElse: () => CulturePreferenceLevel.neutral,
    );
  }
}

class CulturalPreferences {
  const CulturalPreferences({
    this.levels = const {},
    this.updatedAt = 0,
    this.source = 'onboarding',
  });

  final Map<String, CulturePreferenceLevel> levels;
  final int updatedAt;
  final String source;

  bool get isEmpty =>
      levels.values.every((level) => level == CulturePreferenceLevel.neutral);

  CulturePreferenceLevel levelFor(String culture) =>
      levels[culture] ?? CulturePreferenceLevel.neutral;

  Map<String, dynamic> toJson() => {
    'levels': levels.map((key, value) => MapEntry(key, value.value)),
    'updated_at': updatedAt,
    'source': source,
  };

  factory CulturalPreferences.fromJson(Map<String, dynamic> json) {
    final rawLevels = json['levels'];
    final levels = <String, CulturePreferenceLevel>{};
    if (rawLevels is Map) {
      for (final entry in rawLevels.entries) {
        final level = CulturePreferenceLevel.fromValue(entry.value);
        if (level != CulturePreferenceLevel.neutral) {
          levels[entry.key.toString()] = level;
        }
      }
    }
    return CulturalPreferences(
      levels: levels,
      updatedAt: int.tryParse(json['updated_at']?.toString() ?? '') ?? 0,
      source: json['source']?.toString() ?? 'onboarding',
    );
  }
}
