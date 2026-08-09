/// Favori listesinde tutulabilecek en fazla yapım sayısı.
const favoritesCap = 20;

/// Favori türlerin tür-ağırlığı formülündeki taban katsayı.
const favoriteGenreBase = 3.0;

/// Favorinin 0-tabanlı sırasını [0.2, 1.0] ağırlık çarpanına eşler.
double favoriteRankWeight(int rank) {
  final r = rank.clamp(0, favoritesCap - 1);
  return 1.0 - 0.8 * (r / (favoritesCap - 1));
}
