part of '../db_helper.dart';

mixin DbTmdbCacheMixin {
  Future<Database?> get database;

  Future<void> saveTmdbCache(String key, String payload, String locale) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.removeWhere((e) => e['cache_key'] == key);
      DatabaseHelper._mockTmdbCache.add({
        'cache_key': key,
        'payload': payload,
        'fetched_at': timestamp,
        'locale': locale,
      });
      return;
    }
    await db.insert('tmdb_cache', {
      'cache_key': key,
      'payload': payload,
      'fetched_at': timestamp,
      'locale': locale,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getTmdbCache(String key) async {
    final db = await database;
    if (db == null) {
      final matches = DatabaseHelper._mockTmdbCache.where(
        (e) => e['cache_key'] == key,
      );
      return matches.isEmpty ? null : matches.first;
    }
    final results = await db.query(
      'tmdb_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<void> deleteExpiredTmdbCache(int maxAgeMs) async {
    final expiryLimit = DateTime.now().millisecondsSinceEpoch - maxAgeMs;
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.removeWhere(
        (e) => _dbInt(e['fetched_at']) < expiryLimit,
      );
      return;
    }
    await db.delete(
      'tmdb_cache',
      where: 'fetched_at < ?',
      whereArgs: [expiryLimit],
    );
  }

  Future<void> clearTmdbCache() async {
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.clear();
      return;
    }
    await db.delete('tmdb_cache');
  }

  // Anahtarlar artık sürüm önekiyle başladığı için ("v2:/3/...") yol eşleşmesi
  // startsWith değil contains ile yapılır (bkz. TmdbService._cacheKey).
  Future<void> deleteTmdbCachePaths(List<String> prefixes) async {
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.removeWhere((e) {
        final key = e['cache_key'] as String? ?? '';
        return prefixes.any((pref) => key.contains(pref));
      });
      return;
    }
    for (final pref in prefixes) {
      await db.delete(
        'tmdb_cache',
        where: 'cache_key LIKE ?',
        whereArgs: ['%$pref%'],
      );
    }
  }

  /// Verilen önekle BAŞLAMAYAN tüm cache satırlarını siler — cache anahtarı
  /// sürümü değiştiğinde eski neslin tek seferlik temizliği için.
  Future<void> deleteTmdbCacheNotPrefixed(String prefix) async {
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.removeWhere(
        (e) => !((e['cache_key'] as String? ?? '').startsWith(prefix)),
      );
      return;
    }
    await db.delete(
      'tmdb_cache',
      where: 'cache_key NOT LIKE ?',
      whereArgs: ['$prefix%'],
    );
  }

  Future<void> deleteTmdbCacheKeysContaining(List<String> substrings) async {
    final db = await database;
    if (db == null) {
      DatabaseHelper._mockTmdbCache.removeWhere((e) {
        final key = e['cache_key'] as String? ?? '';
        return substrings.any((sub) => key.contains(sub));
      });
      return;
    }
    for (final sub in substrings) {
      await db.delete(
        'tmdb_cache',
        where: 'cache_key LIKE ?',
        whereArgs: ['%$sub%'],
      );
    }
  }
}
