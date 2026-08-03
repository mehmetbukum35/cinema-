import '../models/cultural_preferences.dart';

/// Puanlama davranışından yumuşak kültürel tercih güncellemesi.
/// Kullanıcının "az göster" tercihini tek başına avoid'a çevirmez; yalnızca
/// güçlendirir / iyileştirir (avoid→explore, explore→prefer, prefer→explore).
class CulturalPreferenceLearner {
  /// Yeterli sınıflandırılmış sinyal yoksa veya değişiklik gerekmiyorsa null.
  static CulturalPreferences? suggest({
    required CulturalPreferences current,
    required List<({Set<String> cultures, int rating})> classifiedRatings,
    int? nowMs,
  }) {
    final liked = <String, int>{};
    final disliked = <String, int>{};
    var classifiedLikeEvents = 0;

    for (final row in classifiedRatings) {
      if (row.cultures.isEmpty) continue;
      final isLike = row.rating >= 2;
      final isDislike = row.rating == 0 || row.rating == 1;
      if (!isLike && !isDislike) continue;
      for (final culture in row.cultures) {
        if (isLike) {
          liked[culture] = (liked[culture] ?? 0) + 1;
          classifiedLikeEvents++;
        } else {
          disliked[culture] = (disliked[culture] ?? 0) + 1;
        }
      }
    }

    // Erken / seyrek sinyalde onboarding tercihlerini ezme.
    if (classifiedLikeEvents < 5) return null;

    final next = Map<String, CulturePreferenceLevel>.from(current.levels);
    var changed = false;

    for (final culture in {...liked.keys, ...disliked.keys}) {
      final likeCount = liked[culture] ?? 0;
      final dislikeCount = disliked[culture] ?? 0;
      final seen = likeCount + dislikeCount;
      if (seen < 3) continue;

      final likeRate = likeCount / seen;
      final cur = next[culture] ?? CulturePreferenceLevel.neutral;
      CulturePreferenceLevel? target;

      if (likeRate >= 0.75 && likeCount >= 5) {
        target = CulturePreferenceLevel.prefer;
      } else if (likeRate >= 0.7 &&
          likeCount >= 3 &&
          cur == CulturePreferenceLevel.avoid) {
        // Yanlış "az göster"i yumuşakça geri al.
        target = CulturePreferenceLevel.explore;
      } else if (likeRate >= 0.65 && likeCount >= 4) {
        target = cur.value >= CulturePreferenceLevel.prefer.value
            ? CulturePreferenceLevel.prefer
            : CulturePreferenceLevel.explore;
      } else if (likeRate < 0.35 &&
          dislikeCount >= 3 &&
          cur == CulturePreferenceLevel.prefer) {
        target = CulturePreferenceLevel.explore;
      }

      if (target == null || target == cur) continue;

      // Avoid'a otomatik düşürme yok; yalnızca yükseltme veya yumuşak düşürme.
      final upgrading = target.value > cur.value;
      final softDowngrade =
          cur == CulturePreferenceLevel.prefer &&
          target == CulturePreferenceLevel.explore;
      final healAvoid =
          cur == CulturePreferenceLevel.avoid &&
          target == CulturePreferenceLevel.explore;
      if (!upgrading && !softDowngrade && !healAvoid) continue;

      if (target == CulturePreferenceLevel.neutral) {
        next.remove(culture);
      } else {
        next[culture] = target;
      }
      changed = true;
    }

    if (!changed) return null;
    return CulturalPreferences(
      levels: Map.fromEntries(
        next.entries.where((e) => e.value != CulturePreferenceLevel.neutral),
      ),
      updatedAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      source: 'behavior',
    );
  }
}
