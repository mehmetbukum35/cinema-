part of '../db_helper.dart';

mixin DbSearchHistoryMixin {
  Future<Database?> get database;

  Future<void> addSearchHistory(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cqLower = cleanQuery.toLowerCase();

    if (db == null) {
      DatabaseHelper._mockSearchHistory.removeWhere((e) {
        final existing = (e['query'] as String? ?? '').toLowerCase();
        return existing == cqLower ||
            cqLower.startsWith(existing) ||
            existing.startsWith(cqLower);
      });
      DatabaseHelper._mockSearchHistory.add({
        'query': cleanQuery,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      });
      DatabaseHelper._mockSearchHistory.sort(
        (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
      );
      if (DatabaseHelper._mockSearchHistory.length > 10) {
        DatabaseHelper._mockSearchHistory.removeRange(
          10,
          DatabaseHelper._mockSearchHistory.length,
        );
      }
      return;
    }

    final allHistory = await db.query('search_history', where: 'deleted = 0');
    for (final row in allHistory) {
      final existing = (row['query'] as String? ?? '').toLowerCase();
      if (existing == cqLower ||
          cqLower.startsWith(existing) ||
          existing.startsWith(cqLower)) {
        await db.update(
          'search_history',
          {'deleted': 1, 'updated_at': now},
          where: 'query = ?',
          whereArgs: [row['query']],
        );
      }
    }

    await db.insert('search_history', {
      'query': cleanQuery,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final List<Map<String, dynamic>> oldest = await db.query(
      'search_history',
      where: 'deleted = 0',
      orderBy: 'created_at DESC',
      offset: 10,
    );
    for (final row in oldest) {
      await db.update(
        'search_history',
        {'deleted': 1, 'updated_at': now},
        where: 'query = ?',
        whereArgs: [row['query']],
      );
    }
  }

  Future<List<String>> getSearchHistory() async {
    final db = await database;
    if (db == null) {
      return DatabaseHelper._mockSearchHistory
          .where((m) => m['deleted'] != 1)
          .map((m) => m['query'] as String)
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'search_history',
      where: 'deleted = 0',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => m['query'] as String).toList();
  }

  Future<void> clearSearchHistory() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      for (final e in DatabaseHelper._mockSearchHistory) {
        e['deleted'] = 1;
        e['updated_at'] = now;
      }
      return;
    }
    await db.update('search_history', {'deleted': 1, 'updated_at': now});
  }
}
