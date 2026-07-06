class DnaMovieRef {
  final int id;
  final String title;
  final String? posterPath;
  final bool isTV;

  DnaMovieRef({
    required this.id,
    required this.title,
    this.posterPath,
    required this.isTV,
  });

  String get posterUrl =>
      posterPath != null ? 'https://image.tmdb.org/t/p/w200$posterPath' : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster_path': posterPath,
        'is_tv': isTV,
      };

  factory DnaMovieRef.fromJson(Map<String, dynamic> json) => DnaMovieRef(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        posterPath: json['poster_path'] as String?,
        isTV: json['is_tv'] as bool? ?? false,
      );
}

/// Kullanıcının sinema zevkinin deterministik "kimlik kartı" — puanlama
/// verisinden türetilir, ekranda gösterilir ve backend'e yayınlanıp public web
/// profilinde render edilir. Algoritma tek yerdedir (TasteDnaService); bu model
/// yalnızca sonucu taşır ve JSON'a serileştirir (snapshot sözleşmesi).
class TasteDna {
  /// Arketip anahtarı (lokalizasyon için): 'dark_chronicler', 'world_builder' …
  final String archetypeKey;

  /// İkincil arketip anahtarı; yoksa null.
  final String? secondaryArchetypeKey;

  /// En güçlü türlerin (TMDB tür id'leri), decay'li ağırlığa göre sıralı.
  final List<int> topGenres;

  /// Sık puanlanıp beğenilmeyen tür (kör nokta); yoksa null.
  final int? blindSpotGenre;

  /// Tematik iplikler — beğenilen yapımların en sık keyword isimleri.
  final List<String> themes;

  /// Tema -> Kanıt film referansları.
  final Map<String, List<DnaMovieRef>> themeEvidence;

  /// Çağ imzası: 'modern' (çoğunlukla yeni), 'classic_soul' (eski),
  /// 'time_traveler' (dengeli).
  final String eraKey;

  /// 2015 sonrası beğenilerin oranı [0,1] — eraKey'i besleyen ham sinyal.
  final double modernShare;

  /// Derinlik: 'deep_digger' (az bilinen mücevherler), 'zeitgeist' (popüler),
  /// 'balanced' (yetersiz veri durumunda null).
  final String? depthKey;

  /// Eleştirmen profili: 'tough' (nadir Harika), 'generous', 'balanced' (yetersiz veri durumunda null).
  final String? criticKey;

  /// Harika (3) verme oranı [0,1].
  final double harikaShare;

  /// Zevk kayması (yeterli geçmiş varsa): eski dönemin ve yeni dönemin baskın
  /// türü. Kayma yoksa/ölçülemezse ikisi de null.
  final int? shiftFromGenre;
  final int? shiftToGenre;

  /// Kanıtlı isabet — öneri telemetrisinden genel beğeni oranı [0,1]; örneklem
  /// çok küçükse null.
  final double? accuracy;
  final int accuracySample;

  /// Toplam puanlama sayısı — DNA'nın "olgunluğu".
  final int totalRated;

  /// Üretim anı (ms). Snapshot tazeliği için.
  final int generatedAt;

  const TasteDna({
    required this.archetypeKey,
    this.secondaryArchetypeKey,
    required this.topGenres,
    required this.blindSpotGenre,
    required this.themes,
    this.themeEvidence = const {},
    required this.eraKey,
    required this.modernShare,
    this.depthKey,
    this.criticKey,
    required this.harikaShare,
    required this.shiftFromGenre,
    required this.shiftToGenre,
    required this.accuracy,
    required this.accuracySample,
    required this.totalRated,
    required this.generatedAt,
  });

  /// DNA anlamlı gösterilecek kadar veri var mı? (çok az puanlamada güvenilmez)
  bool get isReady => totalRated >= 5;

  Map<String, dynamic> toJson() => {
        'archetype': archetypeKey,
        'secondary_archetype': secondaryArchetypeKey,
        'top_genres': topGenres,
        'blind_spot': blindSpotGenre,
        'themes': themes,
        'theme_evidence': themeEvidence.map(
          (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
        ),
        'era': eraKey,
        'modern_share': modernShare,
        'depth': depthKey,
        'critic': criticKey,
        'harika_share': harikaShare,
        'shift_from': shiftFromGenre,
        'shift_to': shiftToGenre,
        'accuracy': accuracy,
        'accuracy_sample': accuracySample,
        'total_rated': totalRated,
        'generated_at': generatedAt,
      };

  factory TasteDna.fromJson(Map<String, dynamic> json) => TasteDna(
        archetypeKey: json['archetype'] as String? ?? 'genre_nomad',
        secondaryArchetypeKey: json['secondary_archetype'] as String?,
        topGenres: (json['top_genres'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        blindSpotGenre: (json['blind_spot'] as num?)?.toInt(),
        themes: (json['themes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        themeEvidence: (json['theme_evidence'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(
                k,
                (v as List<dynamic>)
                    .map((e) => DnaMovieRef.fromJson(e as Map<String, dynamic>))
                    .toList(),
              ),
            ) ??
            const {},
        eraKey: json['era'] as String? ?? 'time_traveler',
        modernShare: (json['modern_share'] as num?)?.toDouble() ?? 0.0,
        depthKey: json['depth'] as String?,
        criticKey: json['critic'] as String?,
        harikaShare: (json['harika_share'] as num?)?.toDouble() ?? 0.0,
        shiftFromGenre: (json['shift_from'] as num?)?.toInt(),
        shiftToGenre: (json['shift_to'] as num?)?.toInt(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        accuracySample: (json['accuracy_sample'] as num?)?.toInt() ?? 0,
        totalRated: (json['total_rated'] as num?)?.toInt() ?? 0,
        generatedAt: (json['generated_at'] as num?)?.toInt() ?? 0,
      );
}
