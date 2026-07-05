class Movie {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double voteAverage;
  final String? releaseDate;
  final bool isTV;
  final List<int> genreIds;
  final double popularity;
  final int voteCount;

  Movie({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.overview,
    required this.voteAverage,
    this.releaseDate,
    this.isTV = false,
    this.genreIds = const [],
    this.popularity = 0,
    this.voteCount = 0,
  });

  factory Movie.fromJson(Map<String, dynamic> json, {bool isTV = false}) {
    final parsedId = json['id'] is int
        ? json['id'] as int
        : (int.tryParse(json['id']?.toString() ?? '') ?? 0);
    final parsedIsTv =
        json['is_tv'] == 1 ||
        json['is_tv'] == '1' ||
        json['is_tv'] == true ||
        isTV;
    return Movie(
      id: parsedId,
      title:
          (parsedIsTv
                  ? (json['name'] ?? json['title'])
                  : (json['title'] ?? json['name']))
              as String? ??
          '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String? ?? '',
      voteAverage:
          double.tryParse(json['vote_average']?.toString() ?? '') ?? 0.0,
      releaseDate:
          (parsedIsTv
                  ? (json['first_air_date'] ?? json['release_date'])
                  : (json['release_date'] ?? json['first_air_date']))
              as String?,
      isTV: parsedIsTv,
      genreIds:
          (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .toList() ??
          const [],
      popularity: double.tryParse(json['popularity']?.toString() ?? '') ?? 0.0,
      voteCount: int.tryParse(json['vote_count']?.toString() ?? '') ?? 0,
    );
  }

  String get posterUrl =>
      posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';

  String get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : '';

  String get year {
    final date = releaseDate ?? '';
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  int? personalizedMatchScore;
  int get matchScore =>
      personalizedMatchScore ?? (voteAverage * 10).round().clamp(1, 99);

  // ── Öneri motoru atıfları (oturumluk; kalıcı depoya yazılmaz) ──
  /// UI rozeti için gerekçe: seed film adı ya da arkadaş adı.
  String? recoReason;

  /// Gerekçe tipi: 'seed' ("X'i beğendiğin için") | 'friend' ("X buna bayıldı").
  String? recoReasonType;

  /// Adayın geldiği kaynak — isabet telemetrisi için:
  /// 'discover' | 'seed' | 'friend'.
  String? recoSource;

  Map<String, dynamic> toStorage() => {
    'id': id,
    'title': title,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'overview': overview,
    'vote_average': voteAverage,
    'release_date': releaseDate,
    'isTV': isTV,
    'genre_ids': genreIds,
    'popularity': popularity,
    'vote_count': voteCount,
  };

  factory Movie.fromStorage(Map<String, dynamic> json) => Movie(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    posterPath: json['poster_path'] as String?,
    backdropPath: json['backdrop_path'] as String?,
    overview: json['overview'] as String? ?? '',
    voteAverage: ((json['vote_average'] as num?) ?? 0).toDouble(),
    releaseDate: json['release_date'] as String?,
    isTV: json['isTV'] as bool? ?? false,
    genreIds:
        (json['genre_ids'] as List<dynamic>?)?.map((e) => e as int).toList() ??
        const [],
    popularity: ((json['popularity'] as num?) ?? 0).toDouble(),
    voteCount: json['vote_count'] as int? ?? 0,
  );
}
