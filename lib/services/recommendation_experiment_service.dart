/// Sıralama ağırlıklarının tek doğruluk kaynağı.
///
/// Vaktiyle bu bir A/B deneyiydi: cihaz kimliğinin FNV-1a hash paritesine göre
/// iki kol dağıtılıyordu. Tek kullanıcılı bir kurulumda bu deney değil, veriyi
/// ikiye bölen bir zar atışıydı — "kollar" aynı kişinin iki cihazı oluyor,
/// kıyaslamanın istatistiksel bir anlamı kalmıyor ve her ölçüm yarı yarıya
/// güçsüzleşiyordu (90 günde 515'e karşı 1406 gösterim).
///
/// Atama kaldırıldı; [RecommendationExperimentService.active] tek aktif
/// yapılandırma. İskelet bilerek duruyor: gerçek bir kullanıcı kitlesi olduğunda
/// ikinci bir [RecommendationExperiment] sabiti ve bir atama fonksiyonu eklemek
/// yeterli.
class RecommendationExperiment {
  final String modelVersion;
  final ({double genre, double vote}) genreOnlyWeights;
  final ({double genre, double keyword, double vote}) fullWeights;
  final double preferenceBoostMultiplier;

  const RecommendationExperiment({
    required this.modelVersion,
    required this.genreOnlyWeights,
    required this.fullWeights,
    required this.preferenceBoostMultiplier,
  });
}

class RecommendationExperimentService {
  /// Aktif sıralama yapılandırması — eski `personalization` kolunun ağırlıkları.
  ///
  /// Ağırlıklar değişmediği için `recommendation_v5_ab_personalization` altında
  /// ölçülmüş ham skor dağılımı bu sürüm için de geçerlidir; sürüm adı yalnızca
  /// kolların birleştiği anı telemetride ayırt edilebilir kılmak için değişti.
  /// (Bkz. kalibrasyon raporunun bayatlama kuralı: ağırlık veya boost sabitleri
  /// değişirse `modelVersion` de değişmeli ve dağılım yeniden ölçülmelidir.)
  static const active = RecommendationExperiment(
    modelVersion: 'recommendation_v6',
    genreOnlyWeights: (genre: 0.78, vote: 0.22),
    fullWeights: (genre: 0.50, keyword: 0.30, vote: 0.20),
    preferenceBoostMultiplier: 1.25,
  );
}
