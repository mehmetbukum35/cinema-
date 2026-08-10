part of '../db_helper.dart';

mixin DbRatingsMixin {
  Future<Database?> get database;

  Future<void> saveRating({
    Movie? movie,
    int? movieId,
    bool? isTV,
    required int rating,
    List<int>? genreIds,
    int? updatedAt,
    int? deleted,
    Object? comment = DatabaseHelper.unset,
    Object? isSpoiler = DatabaseHelper.unset,
    Object? isPrivate = DatabaseHelper.unset,
    String metadataLocale = 'tr',
  }) async {
    final db = await database;
    final finalMovieId = movieId ?? movie?.id ?? 0;
    final finalIsTV = isTV ?? movie?.isTV ?? false;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final delVal = deleted ?? 0;

    // Soft-delete tombstone dahil: revive'da created_at / yorum / tür kaybolmasın.
    final existing = await _getRatingRowAny(finalMovieId, finalIsTV);
    final createdAt = existing != null
        ? (_dbInt(existing['created_at'], now))
        : now;
    final String? finalComment = identical(comment, DatabaseHelper.unset)
        ? (existing?['comment'] as String?)
        : comment as String?;
    final int finalIsSpoiler = identical(isSpoiler, DatabaseHelper.unset)
        ? (existing?['is_spoiler'] as int? ?? 0)
        : isSpoiler as int;
    final int finalIsPrivate = identical(isPrivate, DatabaseHelper.unset)
        ? (existing?['is_private'] as int? ?? 0)
        : isPrivate as int;

    // Lean Movie / kısmi kayıt çoğu zaman genreIds=[] taşır; dolu mevcutu
    // boş listeyle ezme (originCountries ile aynı desen).
    final incomingGenreIds = genreIds ?? movie?.genreIds;
    final existingGenreIds = existing != null
        ? _dbIntList(existing['genre_ids'])
        : const <int>[];
    final List<int> finalGenreIds =
        (incomingGenreIds != null && incomingGenreIds.isNotEmpty)
        ? incomingGenreIds
        : (existingGenreIds.isNotEmpty
              ? existingGenreIds
              : (incomingGenreIds ?? const <int>[]));

    final originalLanguage =
        movie?.originalLanguage ?? existing?['original_language'] as String?;
    // Liste uçlarından gelen Movie çoğu zaman originCountries=[] taşır;
    // dolu mevcut değeri boş listeyle ezme (dil alanındaki null-safe desen).
    final String? originCountriesJson =
        (movie != null && movie.originCountries.isNotEmpty)
        ? jsonEncode(movie.originCountries)
        : (existing?['origin_countries'] as String? ??
              (movie != null ? jsonEncode(const <String>[]) : null));

    if (db == null) {
      DatabaseHelper._mockRatings.removeWhere(
        (e) =>
            e['movie_id'] == finalMovieId && e['is_tv'] == (finalIsTV ? 1 : 0),
      );
      DatabaseHelper._mockRatings.add({
        'movie_id': finalMovieId,
        'is_tv': finalIsTV ? 1 : 0,
        'metadata_locale': metadataLocale,
        'rating': rating,
        'genre_ids': jsonEncode(finalGenreIds),
        'created_at': createdAt,
        'updated_at': now,
        'deleted': delVal,
        'title': movie?.title ?? (existing?['title'] as String? ?? ''),
        'poster_path': movie?.posterPath ?? existing?['poster_path'],
        'backdrop_path': movie?.backdropPath ?? existing?['backdrop_path'],
        'overview': movie?.overview ?? (existing?['overview'] as String? ?? ''),
        'vote_average':
            movie?.voteAverage ?? (existing?['vote_average'] as num? ?? 0.0),
        'release_date': movie?.releaseDate ?? existing?['release_date'],
        'popularity':
            movie?.popularity ?? (existing?['popularity'] as num? ?? 0.0),
        'comment': finalComment,
        'is_spoiler': finalIsSpoiler,
        'is_private': finalIsPrivate,
        'original_language': originalLanguage,
        'origin_countries': originCountriesJson,
      });
      return;
    }
    await db.insert('ratings', {
      'movie_id': finalMovieId,
      'is_tv': finalIsTV ? 1 : 0,
      'metadata_locale': metadataLocale,
      'rating': rating,
      'genre_ids': jsonEncode(finalGenreIds),
      'created_at': createdAt,
      'updated_at': now,
      'deleted': delVal,
      'title': movie?.title ?? (existing?['title'] as String? ?? ''),
      'poster_path': movie?.posterPath ?? existing?['poster_path'],
      'backdrop_path': movie?.backdropPath ?? existing?['backdrop_path'],
      'overview': movie?.overview ?? (existing?['overview'] as String? ?? ''),
      'vote_average':
          movie?.voteAverage ?? (existing?['vote_average'] as num? ?? 0.0),
      'release_date': movie?.releaseDate ?? existing?['release_date'],
      'popularity':
          movie?.popularity ?? (existing?['popularity'] as num? ?? 0.0),
      'comment': finalComment,
      'is_spoiler': finalIsSpoiler,
      'is_private': finalIsPrivate,
      'original_language': originalLanguage,
      'origin_countries': originCountriesJson,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Canlı (silinmemiş) puan satırı; soft-delete sonrası null.
  Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) async {
    final row = await _getRatingRowAny(movieId, isTV);
    if (row == null || _dbInt(row['deleted']) == 1) return null;
    return row;
  }

  /// Soft-delete tombstone dahil ham satır — saveRating merge / revive için.
  Future<Map<String, dynamic>?> _getRatingRowAny(int movieId, bool isTV) async {
    final db = await database;
    if (db == null) {
      final match = DatabaseHelper._mockRatings.firstWhere(
        (e) => e['movie_id'] == movieId && e['is_tv'] == (isTV ? 1 : 0),
        orElse: () => <String, dynamic>{},
      );
      return match.isNotEmpty ? match : null;
    }
    final maps = await db.query(
      'ratings',
      where: 'movie_id = ? AND is_tv = ?',
      whereArgs: [movieId, isTV ? 1 : 0],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getRatings() async {
    final db = await database;
    if (db == null) {
      final sorted =
          List<Map<String, dynamic>>.from(DatabaseHelper._mockRatings)..sort(
            (a, b) =>
                _dbInt(a['created_at']).compareTo(_dbInt(b['created_at'])),
          );
      return sorted.where((m) => _dbInt(m['deleted']) != 1).map((m) {
        final genreIdsList = _dbIntList(m['genre_ids']);
        return {
          'id': _dbInt(m['movie_id']),
          'isTV': _dbInt(m['is_tv']) == 1,
          'rating': _dbInt(m['rating']),
          'genreIds': genreIdsList,
          'created_at': _dbInt(m['created_at']),
          'updated_at': _dbInt(m['updated_at'], _dbInt(m['created_at'])),
          'is_private': _dbInt(m['is_private']),
          'movie': Movie(
            id: _dbInt(m['movie_id']),
            title: m['title'] as String? ?? '',
            posterPath: m['poster_path'] as String?,
            backdropPath: m['backdrop_path'] as String?,
            overview: m['overview'] as String? ?? '',
            voteAverage: _dbDouble(m['vote_average']),
            releaseDate: m['release_date'] as String?,
            isTV: _dbInt(m['is_tv']) == 1,
            genreIds: genreIdsList,
            popularity: _dbDouble(m['popularity']),
            originalLanguage: m['original_language'] as String?,
            originCountries: _dbStringList(m['origin_countries']),
          ),
        };
      }).toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'ratings',
      where: 'deleted = 0',
      orderBy: 'created_at ASC',
    );
    return maps.map((m) {
      final genreIdsList = _dbIntList(m['genre_ids']);
      return {
        'id': _dbInt(m['movie_id']),
        'isTV': _dbInt(m['is_tv']) == 1,
        'rating': _dbInt(m['rating']),
        'genreIds': genreIdsList,
        'created_at': _dbInt(m['created_at']),
        'updated_at': _dbInt(m['updated_at']),
        'is_private': _dbInt(m['is_private']),
        'movie': Movie(
          id: _dbInt(m['movie_id']),
          title: m['title'] as String? ?? '',
          posterPath: m['poster_path'] as String?,
          backdropPath: m['backdrop_path'] as String?,
          overview: m['overview'] as String? ?? '',
          voteAverage: _dbDouble(m['vote_average']),
          releaseDate: m['release_date'] as String?,
          isTV: _dbInt(m['is_tv']) == 1,
          genreIds: genreIdsList,
          popularity: _dbDouble(m['popularity']),
          originalLanguage: m['original_language'] as String?,
          originCountries: _dbStringList(m['origin_countries']),
        ),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getRatingsForWeights() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockRatings
          .where((m) => m['deleted'] != 1 && _dbInt(m['is_private']) != 1)
          .map(
            (m) => {
              'id': _dbInt(m['movie_id']),
              'isTV': _dbInt(m['is_tv']) == 1,
              'rating': _dbInt(m['rating']),
              'genreIds': _dbIntList(m['genre_ids']),
              'created_at': _dbInt(m['created_at']),
            },
          )
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'ratings',
      columns: ['movie_id', 'is_tv', 'rating', 'genre_ids', 'created_at'],
      // Gizli puanlar kişisel not; reco tür ağırlıklarına sızmasın.
      where: 'deleted = 0 AND is_private = 0',
    );
    return maps.map((m) {
      final genreIdsList = _dbIntList(m['genre_ids']);
      return {
        'id': _dbInt(m['movie_id']),
        'isTV': _dbInt(m['is_tv']) == 1,
        'rating': _dbInt(m['rating']),
        'genreIds': genreIdsList,
        'created_at': _dbInt(m['created_at']),
      };
    }).toList();
  }

  Future<Set<String>> getRatedIds() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockRatings
          .where((m) => m['deleted'] != 1)
          .map(
            (m) =>
                "${_dbInt(m['is_tv']) == 1 ? 'tv' : 'movie'}_${_dbInt(m['movie_id'])}",
          )
          .toSet();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'ratings',
      columns: ['movie_id', 'is_tv'],
      where: 'deleted = 0',
    );
    return maps
        .map(
          (m) =>
              "${_dbInt(m['is_tv']) == 1 ? 'tv' : 'movie'}_${_dbInt(m['movie_id'])}",
        )
        .toSet();
  }

  Future<void> deleteRating(int movieId, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final idx = DatabaseHelper._mockRatings.indexWhere(
        (e) => e['movie_id'] == movieId && e['is_tv'] == (isTV ? 1 : 0),
      );
      if (idx >= 0) {
        DatabaseHelper._mockRatings[idx]['deleted'] = 1;
        DatabaseHelper._mockRatings[idx]['updated_at'] = now;
      }
      return;
    }
    await db.update(
      'ratings',
      {'deleted': 1, 'updated_at': now},
      where: 'movie_id = ? AND is_tv = ?',
      whereArgs: [movieId, isTV ? 1 : 0],
    );
  }

  /// Yorumu puandan bağımsız siler: comment NULL'a çekilir, puan korunur.
  /// updated_at güncellenir ki değişiklik sync ile sunucuya da yansısın.
  Future<void> deleteComment(int movieId, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final idx = DatabaseHelper._mockRatings.indexWhere(
        (e) => e['movie_id'] == movieId && e['is_tv'] == (isTV ? 1 : 0),
      );
      if (idx >= 0) {
        DatabaseHelper._mockRatings[idx]['comment'] = null;
        DatabaseHelper._mockRatings[idx]['is_spoiler'] = 0;
        DatabaseHelper._mockRatings[idx]['updated_at'] = now;
      }
      return;
    }
    await db.update(
      'ratings',
      {'comment': null, 'is_spoiler': 0, 'updated_at': now},
      where: 'movie_id = ? AND is_tv = ?',
      whereArgs: [movieId, isTV ? 1 : 0],
    );
  }

  /// Yorum yazılmış tüm puanlar ("Yorumlarım" ekranı), en yeni önce.
  Future<List<Map<String, dynamic>>> getCommentedRatings() async {
    final db = await database;
    if (db == null) {
      final list = DatabaseHelper._mockRatings
          .where(
            (m) =>
                m['deleted'] != 1 &&
                ((m['comment'] as String?)?.trim().isNotEmpty ?? false),
          )
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      list.sort(
        (a, b) => _dbInt(b['updated_at']).compareTo(_dbInt(a['updated_at'])),
      );
      return list;
    }
    return db.query(
      'ratings',
      where: "deleted = 0 AND comment IS NOT NULL AND TRIM(comment) <> ''",
      orderBy: 'updated_at DESC',
    );
  }

  Future<int> getRatingCount() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockRatings.where((e) => e['deleted'] != 1).length;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ratings WHERE deleted = 0'),
    );
    return count ?? 0;
  }
}
