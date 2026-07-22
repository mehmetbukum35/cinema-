import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/providers/popular_titles_provider.dart';

void main() {
  test('PopularTitle accepts stringified PDO numeric fields', () {
    final title = PopularTitle.fromJson({
      'rank': '3',
      'votes': '15',
      'tmdb_id': '603',
      'title': 'The Matrix',
      'vote_average': '8.7',
      'is_tv': '1',
      'genre_ids': '["28", 878, "bad"]',
      'popularity': '120.5',
    });

    expect(title.rank, 3);
    expect(title.votes, 15);
    expect(title.movie.id, 603);
    expect(title.movie.voteAverage, 8.7);
    expect(title.movie.isTV, isTrue);
    expect(title.movie.genreIds, [28, 878]);
    expect(title.movie.popularity, 120.5);
  });
}
