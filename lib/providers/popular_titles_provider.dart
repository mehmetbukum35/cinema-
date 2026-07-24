import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import 'auth_provider.dart';

/// Topluluk "Popüler Top 20" tek satırı: başlık + oy sayısı + sıra.
class PopularTitle {
  final Movie movie;
  final int votes;
  final int rank;
  const PopularTitle({
    required this.movie,
    required this.votes,
    required this.rank,
  });

  factory PopularTitle.fromJson(Map<String, dynamic> m) {
    int asInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double asDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    List<int> genres = const [];
    final rawGenres = m['genre_ids'];
    try {
      final decoded = rawGenres is String && rawGenres.isNotEmpty
          ? jsonDecode(rawGenres)
          : rawGenres;
      if (decoded is List) {
        genres = decoded
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .toList();
      }
    } catch (_) {}
    return PopularTitle(
      rank: asInt(m['rank']),
      votes: asInt(m['votes']),
      movie: Movie(
        id: asInt(m['tmdb_id']),
        title: m['title']?.toString() ?? '',
        posterPath: m['poster_path']?.toString(),
        backdropPath: m['backdrop_path']?.toString(),
        overview: m['overview']?.toString() ?? '',
        voteAverage: asDouble(m['vote_average']),
        releaseDate: m['release_date']?.toString(),
        isTV:
            m['is_tv'] == true ||
            m['is_tv'] == 1 ||
            m['is_tv']?.toString() == '1',
        genreIds: genres,
        popularity: asDouble(m['popularity']),
      ),
    );
  }
}

/// `isTV` ile parametreli topluluk popüler listesi. Sunucu cron ile önhesaplar;
/// istemci tarafı bu FutureProvider ile oturum boyunca önbelleğe alır (Keşfet
/// pull-to-refresh'te invalidate edilir).
final popularTitlesProvider = FutureProvider.family<List<PopularTitle>, bool>((
  ref,
  isTV,
) async {
  final api = ref.read(apiServiceProvider);
  final raw = await api.getPopularTitles(isTV);
  return raw
      .whereType<Map<dynamic, dynamic>>()
      .map((m) => PopularTitle.fromJson(Map<String, dynamic>.from(m)))
      .toList(growable: false);
});
