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
          // Normal toggle behavior (remove if exist)
          DatabaseHelper._mockWatchedSeasons.removeAt(index);
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
    final maps = await db.query(
      'watched_seasons',
      where: 'tv_id = ? AND season_number = ?',
      whereArgs: [tvId, seasonNumber],
    );

    if (maps.isNotEmpty) {
      final wasDeleted = maps.first['deleted'] == 1;
      final nextDeleted = deleted ?? (wasDeleted ? 0 : 1);
      await db.update(
        'watched_seasons',
        {'deleted': nextDeleted, 'updated_at': now},
        where: 'tv_id = ? AND season_number = ?',
        whereArgs: [tvId, seasonNumber],
      );
    } else {
      await db.insert('watched_seasons', {
        'tv_id': tvId,
        'season_number': seasonNumber,
        'deleted': deleted ?? 0,
        'updated_at': now,
      });
    }
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
}
