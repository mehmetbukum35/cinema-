import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/services/db_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    // Open an in-memory database at version 1
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (Database db, int version) async {
        // Create initial v1 schema
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
      },
    );

    // Insert dummy v1 data to ensure data is preserved
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

  group('DatabaseHelper Migration Tests', () {
    test('should upgrade database from v1 to v8 successfully', () async {
      // 1. Run upgrade
      await DatabaseHelper().onUpgrade(db, 1, 8);

      // 2. Verify ratings table column schema (v2, v3, v4, v5, v8 additions)
      final ratingsRows = await db.query('ratings');
      expect(ratingsRows, hasLength(1));
      
      final rating = ratingsRows.first;
      expect(rating['movie_id'], 101);
      expect(rating['rating'], 3);
      
      // Check newly added fields
      expect(rating.containsKey('updated_at'), isTrue); // added in v4
      expect(rating.containsKey('deleted'), isTrue);    // added in v4
      expect(rating.containsKey('comment'), isTrue);    // added in v5
      expect(rating.containsKey('is_spoiler'), isTrue); // added in v5
      expect(rating.containsKey('is_private'), isTrue); // added in v8
      
      // Default values should be preserved
      expect(rating['updated_at'], 0);
      expect(rating['deleted'], 0);
      expect(rating['is_spoiler'], 0);
      expect(rating['is_private'], 0);

      // 3. Verify watchlist table schema (v3, v4 additions)
      final watchlistRows = await db.query('watchlist');
      expect(watchlistRows, hasLength(1));
      
      final watchlist = watchlistRows.first;
      expect(watchlist['id'], 202);
      expect(watchlist['title'], 'V1 Watchlist');
      expect(watchlist.containsKey('updated_at'), isTrue);
      expect(watchlist.containsKey('deleted'), isTrue);
      expect(watchlist['updated_at'], 0);
      expect(watchlist['deleted'], 0);

      // 4. Verify new tables are created (v6 tmdb_cache)
      // Querying tmdb_cache should succeed
      final cacheResult = await db.query('tmdb_cache');
      expect(cacheResult, isEmpty);

      // 5. Verify indexes exist (v7 additions)
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
  });
}
