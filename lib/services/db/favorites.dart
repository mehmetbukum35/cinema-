part of '../db_helper.dart';

mixin DbFavoritesMixin {
  Future<Database?> get database;

  Future<void> saveFavorites(
    List<Movie> items,
    bool isTV, {
    String metadataLocale = 'tr',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final isTvFlag = isTV ? 1 : 0;
      // Soft-delete: listeden çıkanları tombstone yap (hard remove değil).
      for (final e in DatabaseHelper._mockFavorites) {
        if (e['is_tv'] == isTvFlag && _dbInt(e['deleted']) != 1) {
          final stillKept = items.any((m) => m.id == e['id']);
          if (!stillKept) {
            e['deleted'] = 1;
            e['updated_at'] = now;
          }
        }
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        DatabaseHelper._mockFavorites.removeWhere(
          (e) => e['id'] == item.id && e['is_tv'] == isTvFlag,
        );
        DatabaseHelper._mockFavorites.add({
          'id': item.id,
          'title': item.title,
          'poster_path': item.posterPath,
          'backdrop_path': item.backdropPath,
          'overview': item.overview,
          'vote_average': item.voteAverage,
          'release_date': item.releaseDate,
          'is_tv': isTvFlag,
          'metadata_locale': metadataLocale,
          'genre_ids': jsonEncode(item.genreIds),
          // created_at = liste içi 0-tabanlı SIRA (rank), zaman damgası değil.
          // DB (sqflite) yolu da 'created_at': i yazar; öneri motoru bunu sıra
          // ağırlığı olarak okur (bkz. PrefsLibraryFacade.favoriteRankWeight).
          'created_at': i,
          'updated_at': now,
          'deleted': 0,
        });
      }
      return;
    }
    await db.transaction((txn) async {
      // Yalnızca aktif satırları tombstone yap — eski tombstone'ların
      // updated_at'ini retouch etme (LWW ile başka cihazdaki revive'ı ezmesin).
      await txn.update(
        'favorites',
        {'deleted': 1, 'updated_at': now},
        where: 'is_tv = ? AND deleted = 0',
        whereArgs: [isTV ? 1 : 0],
      );

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        await txn.insert('favorites', {
          'id': item.id,
          'title': item.title,
          'poster_path': item.posterPath,
          'backdrop_path': item.backdropPath,
          'overview': item.overview,
          'vote_average': item.voteAverage,
          'release_date': item.releaseDate,
          'is_tv': isTV ? 1 : 0,
          'metadata_locale': metadataLocale,
          'genre_ids': jsonEncode(item.genreIds),
          'created_at': i,
          'updated_at': now,
          'deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // Used during remote sync to upsert single favorite record
  Future<void> syncFavorite(
    Movie item,
    bool isTV,
    int createdAt,
    int updatedAt,
    int deleted,
  ) async {
    final db = await database;
    if (db == null) return;
    await db.insert('favorites', {
      'id': item.id,
      'title': item.title,
      'poster_path': item.posterPath,
      'backdrop_path': item.backdropPath,
      'overview': item.overview,
      'vote_average': item.voteAverage,
      'release_date': item.releaseDate,
      'is_tv': isTV ? 1 : 0,
      'genre_ids': jsonEncode(item.genreIds),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted': deleted,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Movie>> getFavorites(bool isTV) async {
    final db = await database;
    if (db == null) {
      final filtered =
          DatabaseHelper._mockFavorites
              .where(
                (e) =>
                    _dbInt(e['is_tv']) == (isTV ? 1 : 0) && e['deleted'] != 1,
              )
              .toList()
            ..sort(
              (a, b) =>
                  _dbInt(a['created_at']).compareTo(_dbInt(b['created_at'])),
            );
      return filtered
          .take(20)
          .map(
            (m) => Movie.fromStorage({
              'id': _dbInt(m['id']),
              'title': m['title'] as String? ?? '',
              'poster_path': m['poster_path'] as String?,
              'backdrop_path': m['backdrop_path'] as String?,
              'overview': m['overview'] as String? ?? '',
              'vote_average': _dbDouble(m['vote_average']),
              'release_date': m['release_date'] as String?,
              'isTV': _dbInt(m['is_tv']) == 1,
              'genre_ids': _dbIntList(m['genre_ids']),
            }),
          )
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'favorites',
      where: 'is_tv = ? AND deleted = 0',
      whereArgs: [isTV ? 1 : 0],
      orderBy: 'created_at ASC, id ASC',
    );
    return maps
        .take(20)
        .map(
          (m) => Movie.fromStorage({
            'id': _dbInt(m['id']),
            'title': m['title'] as String? ?? '',
            'poster_path': m['poster_path'] as String?,
            'backdrop_path': m['backdrop_path'] as String?,
            'overview': m['overview'] as String? ?? '',
            'vote_average': _dbDouble(m['vote_average']),
            'release_date': m['release_date'] as String?,
            'isTV': _dbInt(m['is_tv']) == 1,
            'genre_ids': _dbIntList(m['genre_ids']),
          }),
        )
        .toList();
  }

  /// Sync birleşiminden sonra film/dizi başına en fazla [cap] aktif favori bırakır
  /// ve `created_at` sıra indekslerini 0..n-1 yeniden yazar.
  /// Dönüş: silinen (cap üstü) satır sayısı.
  Future<int> normalizeFavoritesCap({int cap = 20}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    var trimmed = 0;

    if (db == null) {
      for (final isTv in [0, 1]) {
        final active =
            DatabaseHelper._mockFavorites
                .where((e) => e['is_tv'] == isTv && e['deleted'] != 1)
                .toList()
              ..sort((a, b) {
                final rank = ((a['created_at'] as int?) ?? 0).compareTo(
                  (b['created_at'] as int?) ?? 0,
                );
                if (rank != 0) return rank;
                return ((a['id'] as int?) ?? 0).compareTo(
                  (b['id'] as int?) ?? 0,
                );
              });
        for (var i = 0; i < active.length; i++) {
          if (i < cap) {
            if (active[i]['created_at'] != i) {
              active[i]['created_at'] = i;
              active[i]['updated_at'] = now;
            }
          } else {
            active[i]['deleted'] = 1;
            active[i]['updated_at'] = now;
            trimmed++;
          }
        }
      }
      return trimmed;
    }

    await db.transaction((txn) async {
      for (final isTv in [0, 1]) {
        final rows = await txn.query(
          'favorites',
          where: 'is_tv = ? AND deleted = 0',
          whereArgs: [isTv],
          orderBy: 'created_at ASC, id ASC',
        );
        for (var i = 0; i < rows.length; i++) {
          final id = rows[i]['id'] as int;
          if (i < cap) {
            final currentRank = (rows[i]['created_at'] as int?) ?? -1;
            if (currentRank != i) {
              await txn.update(
                'favorites',
                {'created_at': i, 'updated_at': now},
                where: 'id = ? AND is_tv = ?',
                whereArgs: [id, isTv],
              );
            }
          } else {
            await txn.update(
              'favorites',
              {'deleted': 1, 'updated_at': now},
              where: 'id = ? AND is_tv = ?',
              whereArgs: [id, isTv],
            );
            trimmed++;
          }
        }
      }
    });
    return trimmed;
  }

  Future<List<Map<String, dynamic>>> getFavoritesRaw() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockFavorites
          .where((e) => e['deleted'] != 1)
          .toList();
    }
    return await db.query(
      'favorites',
      columns: ['id', 'is_tv', 'genre_ids', 'created_at', 'metadata_locale'],
      where: 'deleted = 0',
    );
  }
}
