part of '../db_helper.dart';

mixin DbClearMixin {
  Future<Database?> get database;

  // Soft delete all data to trigger sync deletions to remote server
  Future<void> softClearAllData() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      for (final list in [
        DatabaseHelper._mockWatchlist,
        DatabaseHelper._mockRatings,
        DatabaseHelper._mockSearchHistory,
        DatabaseHelper._mockWatchedSeasons,
        DatabaseHelper._mockFavorites,
      ]) {
        for (final item in list) {
          item['deleted'] = 1;
          item['updated_at'] = now;
        }
      }
      return;
    }
    await db.update('watchlist', {'deleted': 1, 'updated_at': now});
    await db.update('ratings', {'deleted': 1, 'updated_at': now});
    await db.update('search_history', {'deleted': 1, 'updated_at': now});
    await db.update('watched_seasons', {'deleted': 1, 'updated_at': now});
    await db.update('favorites', {'deleted': 1, 'updated_at': now});
  }

  // Hard delete all user data (account deletion, user-initiated wipe, resetAll).
  Future<void> hardClearAllData() async {
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockWatchlist.clear();
      DatabaseHelper._mockRatings.clear();
      DatabaseHelper._mockSearchHistory.clear();
      DatabaseHelper._mockWatchedSeasons.clear();
      DatabaseHelper._mockFavorites.clear();
      DatabaseHelper._mockTmdbCache.clear();
      return;
    }
    await db.delete('watchlist');
    await db.delete('ratings');
    await db.delete('search_history');
    await db.delete('watched_seasons');
    await db.delete('favorites');
    await db.delete('tmdb_cache');
  }

  // Keeping original clearAllData for backwards compatibility in tests
  Future<void> clearAllData() async => hardClearAllData();

  Future<bool> hasAnyLocalData() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockWatchlist.any((e) => e['deleted'] != 1) ||
          DatabaseHelper._mockRatings.any((e) => e['deleted'] != 1) ||
          DatabaseHelper._mockFavorites.any((e) => e['deleted'] != 1) ||
          DatabaseHelper._mockWatchedSeasons.any((e) => e['deleted'] != 1);
    }

    final ratingsCount =
        Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM ratings WHERE deleted = 0"),
        ) ??
        0;
    if (ratingsCount > 0) return true;

    final watchlistCount =
        Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM watchlist WHERE deleted = 0"),
        ) ??
        0;
    if (watchlistCount > 0) return true;

    final favoritesCount =
        Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM favorites WHERE deleted = 0"),
        ) ??
        0;
    if (favoritesCount > 0) return true;

    final seasonsCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM watched_seasons WHERE deleted = 0",
          ),
        ) ??
        0;
    if (seasonsCount > 0) return true;

    return false;
  }
}
