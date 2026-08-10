part of '../db_helper.dart';

mixin DbWatchlistMixin {
  Future<Database?> get database;

  Future<void> addToWatchlist(
    Movie movie, {
    int? updatedAt,
    int? deleted,
    String metadataLocale = 'tr',
  }) async {
    final db = await database;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final delVal = deleted ?? 0;
    if (db == null) {
      final existingIdx = DatabaseHelper._mockWatchlist.indexWhere(
        (e) => e['id'] == movie.id && e['is_tv'] == (movie.isTV ? 1 : 0),
      );
      final createdAt = existingIdx >= 0
          ? _dbInt(
              DatabaseHelper._mockWatchlist[existingIdx]['created_at'],
              now,
            )
          : now;
      if (existingIdx >= 0) {
        DatabaseHelper._mockWatchlist.removeAt(existingIdx);
      }
      DatabaseHelper._mockWatchlist.add({
        'id': movie.id,
        'title': movie.title,
        'poster_path': movie.posterPath,
        'backdrop_path': movie.backdropPath,
        'overview': movie.overview,
        'vote_average': movie.voteAverage,
        'release_date': movie.releaseDate,
        'is_tv': movie.isTV ? 1 : 0,
        'metadata_locale': metadataLocale,
        'genre_ids': jsonEncode(movie.genreIds),
        'created_at': createdAt,
        'updated_at': now,
        'deleted': delVal,
      });
      return;
    }
    // Soft-delete revive: eski created_at korunsun (sıra + sync LWW).
    final existing = await db.query(
      'watchlist',
      columns: ['created_at'],
      where: 'id = ? AND is_tv = ?',
      whereArgs: [movie.id, movie.isTV ? 1 : 0],
      limit: 1,
    );
    final createdAt = existing.isNotEmpty
        ? _dbInt(existing.first['created_at'], now)
        : now;
    await db.insert('watchlist', {
      'id': movie.id,
      'title': movie.title,
      'poster_path': movie.posterPath,
      'backdrop_path': movie.backdropPath,
      'overview': movie.overview,
      'vote_average': movie.voteAverage,
      'release_date': movie.releaseDate,
      'is_tv': movie.isTV ? 1 : 0,
      'metadata_locale': metadataLocale,
      'genre_ids': jsonEncode(movie.genreIds),
      'created_at': createdAt,
      'updated_at': now,
      'deleted': delVal,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFromWatchlist(int id, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final idx = DatabaseHelper._mockWatchlist.indexWhere(
        (e) => e['id'] == id && e['is_tv'] == (isTV ? 1 : 0),
      );
      if (idx >= 0) {
        DatabaseHelper._mockWatchlist[idx]['deleted'] = 1;
        DatabaseHelper._mockWatchlist[idx]['updated_at'] = now;
      }
      return;
    }
    await db.update(
      'watchlist',
      {'deleted': 1, 'updated_at': now},
      where: 'id = ? AND is_tv = ?',
      whereArgs: [id, isTV ? 1 : 0],
    );
  }

  Future<bool> isInWatchlist(int id, bool isTV) async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchlist.any(
        (e) =>
            e['id'] == id && e['is_tv'] == (isTV ? 1 : 0) && e['deleted'] != 1,
      );
    }
    final maps = await db.query(
      'watchlist',
      columns: ['id'],
      where: 'id = ? AND is_tv = ? AND deleted = 0',
      whereArgs: [id, isTV ? 1 : 0],
    );
    return maps.isNotEmpty;
  }

  Future<List<Movie>> getWatchlist() async {
    final db = await database;
    if (db == null) {
      final sorted =
          List<Map<String, dynamic>>.from(DatabaseHelper._mockWatchlist)..sort(
            (a, b) =>
                _dbInt(b['created_at']).compareTo(_dbInt(a['created_at'])),
          ); // newest first
      return sorted
          .where((m) => m['deleted'] != 1)
          .map(
            (m) => Movie.fromStorage({
              'id': _dbInt(m['id']),
              'title': m['title'] as String? ?? '',
              'poster_path': m['poster_path'] as String?,
              'backdrop_path': m['backdrop_path'] as String?,
              'overview': m['overview'] as String? ?? '',
              'vote_average': _dbDouble(m['vote_average']),
              'release_date': m['release_date'] as String?,
              'isTV': (_dbInt(m['is_tv'])) == 1,
              'genre_ids': _dbIntList(m['genre_ids']),
            }),
          )
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'watchlist',
      where: 'deleted = 0',
      orderBy: 'created_at DESC',
    );
    return maps
        .map(
          (m) => Movie.fromStorage({
            'id': _dbInt(m['id']),
            'title': m['title'] as String? ?? '',
            'poster_path': m['poster_path'] as String?,
            'backdrop_path': m['backdrop_path'] as String?,
            'overview': m['overview'] as String? ?? '',
            'vote_average': _dbDouble(m['vote_average']),
            'release_date': m['release_date'] as String?,
            'isTV': (_dbInt(m['is_tv'])) == 1,
            'genre_ids': _dbIntList(m['genre_ids']),
          }),
        )
        .toList();
  }

  /// Sadece sayı gerektiğinde tüm satırları `Movie`'ye çevirmeden (genre-id
  /// JSON çözümü dahil) hızlı sayım — bkz. getRatingCount() (ratings.dart).
  Future<int> getWatchlistCount() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchlist
          .where((e) => e['deleted'] != 1)
          .length;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM watchlist WHERE deleted = 0'),
    );
    return count ?? 0;
  }

  Future<List<Map<String, dynamic>>> getWatchlistRaw() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchlist
          .where((e) => e['deleted'] != 1)
          .toList();
    }
    return await db.query(
      'watchlist',
      columns: ['id', 'is_tv', 'metadata_locale'],
      where: 'deleted = 0',
    );
  }
}
