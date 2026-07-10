import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/models/movie.dart';

/// DatabaseHelper'ın gerçek SQL yolunu test eder: ffi in-memory veritabanı
/// üretim şemasıyla (onCreate) açılıp DatabaseHelper'a enjekte edilir; mock
/// listeler devreye girmez. Migration testleri ise v1 şemasından başlar.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final helper = DatabaseHelper();

  Movie movie(int id, String title, {bool isTV = false}) => Movie(
    id: id,
    title: title,
    posterPath: '/p$id.jpg',
    backdropPath: '/b$id.jpg',
    overview: 'overview $id',
    voteAverage: 7.0,
    releaseDate: '2020-01-01',
    isTV: isTV,
    genreIds: const [18, 28],
    popularity: 5.0,
  );

  Future<void> createV1Schema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ratings (
        movie_id INTEGER,
        is_tv INTEGER,
        rating INTEGER,
        genre_ids TEXT,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER,
        title TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        vote_average REAL,
        release_date TEXT,
        is_tv INTEGER,
        genre_ids TEXT,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        id INTEGER,
        title TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        vote_average REAL,
        release_date TEXT,
        is_tv INTEGER,
        genre_ids TEXT,
        created_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE watched_seasons (
        tv_id INTEGER,
        season_number INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE search_history (
        query TEXT,
        created_at INTEGER
      )
    ''');
  }

  group('DatabaseHelper migration', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: createV1Schema,
      );
      await db.insert('ratings', {
        'movie_id': 101,
        'is_tv': 0,
        'rating': 3,
        'genre_ids': '[28]',
        'created_at': 1000,
      });
      await db.insert('watchlist', {
        'id': 202,
        'title': 'V1 Watchlist',
        'is_tv': 1,
        'created_at': 1100,
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('should upgrade database from v1 to v8 successfully', () async {
      await helper.onUpgrade(db, 1, 8);

      final ratingsRows = await db.query('ratings');
      expect(ratingsRows, hasLength(1));

      final rating = ratingsRows.first;
      expect(rating['movie_id'], 101);
      expect(rating['rating'], 3);

      expect(rating.containsKey('updated_at'), isTrue); // added in v4
      expect(rating.containsKey('deleted'), isTrue); // added in v4
      expect(rating.containsKey('comment'), isTrue); // added in v5
      expect(rating.containsKey('is_spoiler'), isTrue); // added in v5
      expect(rating.containsKey('is_private'), isTrue); // added in v8

      expect(rating['updated_at'], 0);
      expect(rating['deleted'], 0);
      expect(rating['is_spoiler'], 0);
      expect(rating['is_private'], 0);

      final watchlistRows = await db.query('watchlist');
      expect(watchlistRows, hasLength(1));

      final watchlist = watchlistRows.first;
      expect(watchlist['id'], 202);
      expect(watchlist['title'], 'V1 Watchlist');
      expect(watchlist['updated_at'], 0);
      expect(watchlist['deleted'], 0);

      // v6: tmdb_cache tablosu oluşmuş olmalı
      final cacheResult = await db.query('tmdb_cache');
      expect(cacheResult, isEmpty);

      // v7: delta-sync indeksleri
      final indices = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final indexNames = indices.map((row) => row['name'] as String).toList();

      expect(indexNames, contains('idx_watchlist_updated_at'));
      expect(indexNames, contains('idx_ratings_updated_at'));
      expect(indexNames, contains('idx_favorites_updated_at'));
      expect(indexNames, contains('idx_watched_seasons_updated_at'));
      expect(indexNames, contains('idx_search_history_updated_at'));
    });

    test('migrated schema matches fresh onCreate schema (no drift)', () async {
      await helper.onUpgrade(db, 1, 8);

      final migratedColumns = <String, Set<String>>{};
      const tables = [
        'watchlist',
        'ratings',
        'search_history',
        'watched_seasons',
        'favorites',
        'tmdb_cache',
      ];
      for (final table in tables) {
        final info = await db.rawQuery('PRAGMA table_info($table)');
        migratedColumns[table] = info.map((r) => r['name'] as String).toSet();
      }
      await db.close();

      final fresh = await openDatabase(
        inMemoryDatabasePath,
        version: 8,
        onCreate: helper.onCreate,
      );
      try {
        for (final table in tables) {
          final info = await fresh.rawQuery('PRAGMA table_info($table)');
          final freshCols = info.map((r) => r['name'] as String).toSet();
          expect(
            migratedColumns[table],
            freshCols,
            reason:
                '$table tablosu migration sonrası taze şemayla uyuşmuyor — '
                'yeni kolon eklerken hem onCreate hem onUpgrade güncellenmeli',
          );
        }
      } finally {
        await fresh.close();
      }

      // tearDown'daki close çift çağrılmasın diye yeniden aç.
      db = await openDatabase(inMemoryDatabasePath, version: 1);
    });
  });

  // ─── Gerçek şema üzerinde CRUD testleri ───────────────────────────────────

  group('with production schema', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 8,
        onCreate: helper.onCreate,
      );
      DatabaseHelper.databaseInstance = db;
    });

    tearDown(() async {
      DatabaseHelper.databaseInstance = null;
      await db.close();
    });

    group('ratings', () {
      test('saveRating + getRating roundtrip persists all fields', () async {
        await helper.saveRating(
          movie: movie(1, 'Film A'),
          rating: 3,
          updatedAt: 1000,
          comment: 'güzeldi',
          isSpoiler: 1,
          isPrivate: 1,
        );

        final row = await helper.getRating(1, false);
        expect(row, isNotNull);
        expect(row!['rating'], 3);
        expect(row['title'], 'Film A');
        expect(row['poster_path'], '/p1.jpg');
        expect(row['genre_ids'], '[18,28]');
        expect(row['created_at'], 1000);
        expect(row['updated_at'], 1000);
        expect(row['comment'], 'güzeldi');
        expect(row['is_spoiler'], 1);
        expect(row['is_private'], 1);
        expect(row['deleted'], 0);
      });

      test('re-rating preserves created_at but bumps updated_at', () async {
        await helper.saveRating(movie: movie(1, 'Film A'), rating: 2, updatedAt: 1000);
        await helper.saveRating(movie: movie(1, 'Film A'), rating: 3, updatedAt: 2000);

        final row = await helper.getRating(1, false);
        expect(row!['rating'], 3);
        expect(row['created_at'], 1000);
        expect(row['updated_at'], 2000);
      });

      test('saveRating with only movieId preserves existing metadata', () async {
        // afbbd4c regresyonu: kısmi kayıt (yalnızca puan) metadata'yı silmemeli.
        await helper.saveRating(
          movie: movie(1, 'Film A'),
          rating: 3,
          comment: 'yorum',
          isSpoiler: 1,
        );

        await helper.saveRating(movieId: 1, isTV: false, rating: 1);

        final row = await helper.getRating(1, false);
        expect(row!['rating'], 1);
        expect(row['title'], 'Film A');
        expect(row['poster_path'], '/p1.jpg');
        expect(row['overview'], 'overview 1');
        expect(row['comment'], 'yorum');
        expect(row['is_spoiler'], 1);
      });

      test('movie and tv with same id are independent rows', () async {
        await helper.saveRating(movie: movie(7, 'Film'), rating: 1);
        await helper.saveRating(movie: movie(7, 'Dizi', isTV: true), rating: 3);

        final movieRow = await helper.getRating(7, false);
        final tvRow = await helper.getRating(7, true);
        expect(movieRow!['rating'], 1);
        expect(tvRow!['rating'], 3);
        expect(await helper.getRatingCount(), 2);
      });

      test('deleteRating is a soft delete visible to sync', () async {
        await helper.saveRating(movie: movie(1, 'Film A'), rating: 3, updatedAt: 1000);
        await helper.deleteRating(1, false);

        // Görünür API'lerden düşer...
        expect(await helper.getRating(1, false), isNull);
        expect(await helper.getRatings(), isEmpty);
        expect(await helper.getRatedIds(), isEmpty);
        expect(await helper.getRatingCount(), 0);

        // ...ama satır deleted=1 ve ilerlemiş updated_at ile durur (push için).
        final raw = await db.query('ratings');
        expect(raw, hasLength(1));
        expect(raw.first['deleted'], 1);
        expect(raw.first['updated_at'] as int, greaterThan(1000));
      });

      test('getRatings maps rows to Movie and sorts oldest first', () async {
        await helper.saveRating(movie: movie(2, 'Yeni'), rating: 3, updatedAt: 2000);
        await helper.saveRating(movie: movie(1, 'Eski'), rating: 2, updatedAt: 1000);

        final rows = await helper.getRatings();
        expect(rows, hasLength(2));
        expect(rows.first['id'], 1);
        expect(rows.last['id'], 2);

        final m = rows.first['movie'] as Movie;
        expect(m.title, 'Eski');
        expect(m.genreIds, [18, 28]);
        expect(rows.first['genreIds'], [18, 28]);
      });

      test('getRatingsForWeights and getRatedIds exclude deleted rows', () async {
        await helper.saveRating(movie: movie(1, 'Kalan'), rating: 3);
        await helper.saveRating(movie: movie(2, 'Silinen', isTV: true), rating: 0);
        await helper.deleteRating(2, true);

        final weights = await helper.getRatingsForWeights();
        expect(weights, hasLength(1));
        expect(weights.first['id'], 1);

        expect(await helper.getRatedIds(), {'movie_1'});
      });

      test('sync path: explicit deleted=1 rating stays hidden', () async {
        await helper.saveRating(
          movieId: 5,
          isTV: false,
          rating: 2,
          updatedAt: 9000,
          deleted: 1,
        );
        expect(await helper.getRating(5, false), isNull);
        final raw = await db.query('ratings');
        expect(raw.first['deleted'], 1);
        expect(raw.first['updated_at'], 9000);
      });
    });

    group('watchlist', () {
      test('add, check and list newest first', () async {
        await helper.addToWatchlist(movie(1, 'Eski'), updatedAt: 1000);
        await helper.addToWatchlist(movie(2, 'Yeni'), updatedAt: 2000);

        expect(await helper.isInWatchlist(1, false), isTrue);
        expect(await helper.isInWatchlist(1, true), isFalse);

        final list = await helper.getWatchlist();
        expect(list.map((m) => m.title).toList(), ['Yeni', 'Eski']);
        expect(list.first.genreIds, [18, 28]);
      });

      test('remove is a soft delete, re-adding resurrects', () async {
        await helper.addToWatchlist(movie(1, 'Film'), updatedAt: 1000);
        await helper.removeFromWatchlist(1, false);

        expect(await helper.isInWatchlist(1, false), isFalse);
        final raw = await db.query('watchlist');
        expect(raw, hasLength(1));
        expect(raw.first['deleted'], 1);
        expect(raw.first['updated_at'] as int, greaterThan(1000));

        await helper.addToWatchlist(movie(1, 'Film'), updatedAt: 3000);
        expect(await helper.isInWatchlist(1, false), isTrue);
        expect(await db.query('watchlist'), hasLength(1));
      });

      test('same id movie and tv are distinct entries', () async {
        await helper.addToWatchlist(movie(9, 'Film'));
        await helper.addToWatchlist(movie(9, 'Dizi', isTV: true));
        await helper.removeFromWatchlist(9, false);

        expect(await helper.isInWatchlist(9, false), isFalse);
        expect(await helper.isInWatchlist(9, true), isTrue);
      });
    });

    group('search history', () {
      test('stores queries newest first and dedupes', () async {
        await helper.addSearchHistory('matrix');
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await helper.addSearchHistory('dune');
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await helper.addSearchHistory('matrix');

        final history = await helper.getSearchHistory();
        expect(history, ['matrix', 'dune']);
      });

      test('caps visible history at 10 by soft-deleting oldest', () async {
        for (var i = 0; i < 12; i++) {
          await helper.addSearchHistory('query-$i');
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }

        final history = await helper.getSearchHistory();
        expect(history, hasLength(10));
        expect(history.first, 'query-11');
        expect(history, isNot(contains('query-0')));
        expect(history, isNot(contains('query-1')));

        // Satırlar silinmez, soft-delete edilir (sync'e yansıması için).
        expect(await db.query('search_history'), hasLength(12));
      });

      test('clearSearchHistory soft-deletes everything', () async {
        await helper.addSearchHistory('matrix');
        await helper.addSearchHistory('dune');
        await helper.clearSearchHistory();

        expect(await helper.getSearchHistory(), isEmpty);
        final raw = await db.query('search_history');
        expect(raw, hasLength(2));
        expect(raw.every((r) => r['deleted'] == 1), isTrue);
      });
    });

    group('watched seasons', () {
      test('toggle adds, removes and resurrects a season', () async {
        await helper.toggleSeason(100, 1);
        expect(await helper.getWatchedSeasons(100), {1});

        await helper.toggleSeason(100, 1);
        expect(await helper.getWatchedSeasons(100), isEmpty);
        // Soft delete: satır sync için durur.
        expect(await db.query('watched_seasons'), hasLength(1));

        await helper.toggleSeason(100, 1);
        expect(await helper.getWatchedSeasons(100), {1});
      });

      test('seasons are scoped per tv id', () async {
        await helper.toggleSeason(100, 1);
        await helper.toggleSeason(100, 2);
        await helper.toggleSeason(200, 5);

        expect(await helper.getWatchedSeasons(100), {1, 2});
        expect(await helper.getWatchedSeasons(200), {5});
      });

      test('sync path: explicit deleted and updatedAt are applied', () async {
        await helper.toggleSeason(100, 3, updatedAt: 5000, deleted: 1);

        expect(await helper.getWatchedSeasons(100), isEmpty);
        final raw = await db.query('watched_seasons');
        expect(raw.first['deleted'], 1);
        expect(raw.first['updated_at'], 5000);

        // Sunucudan gelen "geri al" da uygulanabilmeli.
        await helper.toggleSeason(100, 3, updatedAt: 6000, deleted: 0);
        expect(await helper.getWatchedSeasons(100), {3});
      });
    });

    group('favorites', () {
      test('saveFavorites replaces the set and preserves order', () async {
        await helper.saveFavorites([movie(1, 'A'), movie(2, 'B')], false);

        var favs = await helper.getFavorites(false);
        expect(favs.map((m) => m.title).toList(), ['A', 'B']);

        await helper.saveFavorites([movie(3, 'C'), movie(1, 'A')], false);
        favs = await helper.getFavorites(false);
        expect(favs.map((m) => m.title).toList(), ['C', 'A']);

        // Listeden çıkan eski favori soft-delete edilir.
        final gone = await db.query(
          'favorites',
          where: 'id = 2 AND is_tv = 0',
        );
        expect(gone, hasLength(1));
        expect(gone.first['deleted'], 1);
      });

      test('movie favorites do not clobber tv favorites', () async {
        await helper.saveFavorites([movie(1, 'Film', isTV: false)], false);
        await helper.saveFavorites([movie(2, 'Dizi', isTV: true)], true);
        await helper.saveFavorites([movie(3, 'Başka Film')], false);

        expect(
          (await helper.getFavorites(true)).map((m) => m.title).toList(),
          ['Dizi'],
        );
        expect(
          (await helper.getFavorites(false)).map((m) => m.title).toList(),
          ['Başka Film'],
        );
      });

      test('syncFavorite upserts with explicit timestamps', () async {
        await helper.syncFavorite(movie(1, 'Uzak'), false, 100, 200, 0);

        final favs = await helper.getFavorites(false);
        expect(favs.map((m) => m.title).toList(), ['Uzak']);
        final raw = await db.query('favorites');
        expect(raw.first['created_at'], 100);
        expect(raw.first['updated_at'], 200);

        // Sunucudan gelen silme görünür listeden düşürür.
        await helper.syncFavorite(movie(1, 'Uzak'), false, 100, 300, 1);
        expect(await helper.getFavorites(false), isEmpty);
      });

      test('getFavoritesRaw excludes deleted rows', () async {
        await helper.saveFavorites([movie(1, 'A')], false);
        await helper.saveFavorites([movie(2, 'B')], false); // A soft-deleted

        final raw = await helper.getFavoritesRaw();
        expect(raw, hasLength(1));
      });
    });

    group('clear / reset', () {
      Future<void> seedAllTables() async {
        await helper.saveRating(movie: movie(1, 'Film'), rating: 3, updatedAt: 1000);
        await helper.addToWatchlist(movie(2, 'Liste'), updatedAt: 1000);
        await helper.addSearchHistory('matrix');
        await helper.toggleSeason(100, 1, updatedAt: 1000);
        await helper.saveFavorites([movie(3, 'Favori')], false);
        await helper.saveTmdbCache('v2:/3/movie/1', '{"a":1}', 'tr');
      }

      test('softClearAllData marks all rows deleted for sync push', () async {
        await seedAllTables();
        await helper.softClearAllData();

        expect(await helper.getRatings(), isEmpty);
        expect(await helper.getWatchlist(), isEmpty);
        expect(await helper.getSearchHistory(), isEmpty);
        expect(await helper.getWatchedSeasons(100), isEmpty);
        expect(await helper.getFavorites(false), isEmpty);

        // Satırlar durur, deleted=1 ve güncel updated_at ile.
        for (final table in [
          'ratings',
          'watchlist',
          'search_history',
          'watched_seasons',
          'favorites',
        ]) {
          final rows = await db.query(table);
          expect(rows, isNotEmpty, reason: '$table boşaltılmamalı');
          expect(
            rows.every((r) => r['deleted'] == 1),
            isTrue,
            reason: '$table satırları deleted=1 olmalı',
          );
          expect(
            rows.every((r) => (r['updated_at'] as int) > 1000),
            isTrue,
            reason: '$table updated_at push için ilerlemeli',
          );
        }
      });

      test('hardClearAllData wipes every table including tmdb cache', () async {
        await seedAllTables();
        await helper.hardClearAllData();

        for (final table in [
          'ratings',
          'watchlist',
          'search_history',
          'watched_seasons',
          'favorites',
          'tmdb_cache',
        ]) {
          expect(
            await db.query(table),
            isEmpty,
            reason: '$table tamamen silinmeli',
          );
        }
      });

      test('hasAnyLocalData reflects visible (non-deleted) data', () async {
        expect(await helper.hasAnyLocalData(), isFalse);

        await helper.saveRating(movie: movie(1, 'Film'), rating: 3);
        expect(await helper.hasAnyLocalData(), isTrue);

        await helper.softClearAllData();
        expect(await helper.hasAnyLocalData(), isFalse);
      });
    });

    group('tmdb cache', () {
      test('save + get roundtrip and overwrite on same key', () async {
        await helper.saveTmdbCache('v2:/3/movie/1', '{"a":1}', 'tr');
        await helper.saveTmdbCache('v2:/3/movie/1', '{"a":2}', 'en');

        final row = await helper.getTmdbCache('v2:/3/movie/1');
        expect(row, isNotNull);
        expect(row!['payload'], '{"a":2}');
        expect(row['locale'], 'en');
        expect(await db.query('tmdb_cache'), hasLength(1));

        expect(await helper.getTmdbCache('yok'), isNull);
      });

      test('deleteExpiredTmdbCache removes only stale entries', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('tmdb_cache', {
          'cache_key': 'old',
          'payload': '{}',
          'fetched_at': now - 10000,
          'locale': 'tr',
        });
        await db.insert('tmdb_cache', {
          'cache_key': 'fresh',
          'payload': '{}',
          'fetched_at': now,
          'locale': 'tr',
        });

        await helper.deleteExpiredTmdbCache(5000);

        final keys = (await db.query('tmdb_cache'))
            .map((r) => r['cache_key'])
            .toList();
        expect(keys, ['fresh']);
      });

      test('deleteTmdbCachePaths matches by substring', () async {
        await helper.saveTmdbCache('v2:/3/movie/popular?page=1', '{}', 'tr');
        await helper.saveTmdbCache('v2:/3/tv/popular?page=1', '{}', 'tr');

        await helper.deleteTmdbCachePaths(['/3/movie/popular']);

        final keys = (await db.query('tmdb_cache'))
            .map((r) => r['cache_key'])
            .toList();
        expect(keys, ['v2:/3/tv/popular?page=1']);
      });

      test('deleteTmdbCacheNotPrefixed keeps only current generation', () async {
        await helper.saveTmdbCache('v2:/3/movie/1', '{}', 'tr');
        await helper.saveTmdbCache('/3/movie/2', '{}', 'tr'); // eski nesil

        await helper.deleteTmdbCacheNotPrefixed('v2:');

        final keys = (await db.query('tmdb_cache'))
            .map((r) => r['cache_key'])
            .toList();
        expect(keys, ['v2:/3/movie/1']);
      });

      test('deleteTmdbCacheKeysContaining removes all matches', () async {
        await helper.saveTmdbCache('v2:/3/movie/1?lang=tr', '{}', 'tr');
        await helper.saveTmdbCache('v2:/3/movie/1?lang=en', '{}', 'en');
        await helper.saveTmdbCache('v2:/3/tv/9', '{}', 'tr');

        await helper.deleteTmdbCacheKeysContaining(['/3/movie/1']);

        final keys = (await db.query('tmdb_cache'))
            .map((r) => r['cache_key'])
            .toList();
        expect(keys, ['v2:/3/tv/9']);
      });

      test('clearTmdbCache empties the table', () async {
        await helper.saveTmdbCache('v2:/3/movie/1', '{}', 'tr');
        await helper.clearTmdbCache();
        expect(await db.query('tmdb_cache'), isEmpty);
      });
    });
  });
}
