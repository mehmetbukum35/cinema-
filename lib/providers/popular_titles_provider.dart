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
}

/// `isTV` ile parametreli topluluk popüler listesi. Sunucu cron ile önhesaplar;
/// istemci tarafı bu FutureProvider ile oturum boyunca önbelleğe alır (Keşfet
/// pull-to-refresh'te invalidate edilir).
final popularTitlesProvider =
    FutureProvider.family<List<PopularTitle>, bool>((ref, isTV) async {
  final api = ref.read(apiServiceProvider);
  final raw = await api.getPopularTitles(isTV);
  return raw
      .whereType<Map<String, dynamic>>()
      .map(_fromJson)
      .toList(growable: false);
});

PopularTitle _fromJson(Map<String, dynamic> m) {
  List<int> genres = const [];
  final g = m['genre_ids'];
  if (g is String && g.isNotEmpty) {
    try {
      genres = (jsonDecode(g) as List<dynamic>).map((e) => e as int).toList();
    } catch (_) {}
  } else if (g is List) {
    genres = g.map((e) => e as int).toList();
  }
  return PopularTitle(
    rank: (m['rank'] as num?)?.toInt() ?? 0,
    votes: (m['votes'] as num?)?.toInt() ?? 0,
    movie: Movie(
      id: (m['tmdb_id'] as num).toInt(),
      title: (m['title'] as String?) ?? '',
      posterPath: m['poster_path'] as String?,
      backdropPath: m['backdrop_path'] as String?,
      overview: (m['overview'] as String?) ?? '',
      voteAverage: (m['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: m['release_date'] as String?,
      isTV: m['is_tv'] == true,
      genreIds: genres,
      popularity: (m['popularity'] as num?)?.toDouble() ?? 0.0,
    ),
  );
}
