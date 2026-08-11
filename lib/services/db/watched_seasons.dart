part of '../db_helper.dart';

mixin DbWatchedSeasonsMixin {
  Future<Database?> get database;

  Future<void> toggleSeason(
    int tvId,
    int seasonNumber, {
    int? updatedAt,
    int? deleted,
  }) async {
    final db = await database;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final index = DatabaseHelper._mockWatchedSeasons.indexWhere(
        (e) => e['tv_id'] == tvId && e['season_number'] == seasonNumber,
      );
      if (index >= 0) {
        if (deleted == null) {
          // Normal toggle: soft-delete / revive (DB yolu ile aynı).
          final wasDeleted =
              _dbInt(DatabaseHelper._mockWatchedSeasons[index]['deleted']) == 1;
          DatabaseHelper._mockWatchedSeasons[index]['deleted'] = wasDeleted
              ? 0
              : 1;
          DatabaseHelper._mockWatchedSeasons[index]['updated_at'] = now;
        } else {
          DatabaseHelper._mockWatchedSeasons[index]['deleted'] = deleted;
          DatabaseHelper._mockWatchedSeasons[index]['updated_at'] = now;
        }
      } else {
        DatabaseHelper._mockWatchedSeasons.add({
          'tv_id': tvId,
          'season_number': seasonNumber,
          'deleted': deleted ?? 0,
          'updated_at': now,
        });
      }
      return;
    }

    // Atomik upsert: SELECT→INSERT yarışı çift dokunuşta PK hatasına düşmesin.
    // deleted == null → mevcut satırda flip, yoksa 0 ile ekle.
    // deleted != null → o değeri zorla yaz.
    final hasExplicit = deleted != null ? 1 : 0;
    final explicitVal = deleted ?? 0;
    await db.execute(
      '''
      INSERT INTO watched_seasons (tv_id, season_number, deleted, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(tv_id, season_number) DO UPDATE SET
        deleted = CASE
          WHEN ? = 1 THEN ?
          ELSE CASE WHEN watched_seasons.deleted = 1 THEN 0 ELSE 1 END
        END,
        updated_at = ?
      ''',
      [tvId, seasonNumber, explicitVal, now, hasExplicit, explicitVal, now],
    );
  }

  Future<Set<int>> getWatchedSeasons(int tvId) async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchedSeasons
          .where((e) => e['tv_id'] == tvId && e['deleted'] != 1)
          .map((e) => e['season_number'] as int)
          .toSet();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'watched_seasons',
      where: 'tv_id = ? AND deleted = 0',
      whereArgs: [tvId],
    );
    return maps.map((m) => m['season_number'] as int).toSet();
  }

  Future<int> getWatchedSeasonCount() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchedSeasons
          .where((e) => e['deleted'] != 1)
          .length;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM watched_seasons WHERE deleted = 0',
      ),
    );
    return count ?? 0;
  }
}
