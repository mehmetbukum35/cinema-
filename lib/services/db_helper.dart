import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/movie.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;
  static bool _useInMemoryMock = false;

  // In-memory mock storage for Web, Desktop (Windows) and unsupported platforms
  static final List<Map<String, dynamic>> _mockWatchlist = [];
  static final List<Map<String, dynamic>> _mockRatings = [];
  static final List<Map<String, dynamic>> _mockSearchHistory = [];
  static final List<Map<String, dynamic>> _mockWatchedSeasons = [];
  static final List<Map<String, dynamic>> _mockFavorites = [];
  static final List<Map<String, dynamic>> _mockTmdbCache = [];

  DatabaseHelper._internal();

  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  static set databaseInstance(Database? db) {
    _database = db;
  }

  Future<Database?> get database async {
    if (_database != null) return _database;
    if (_useInMemoryMock) return null;
    if (kIsWeb) {
      _useInMemoryMock = true;
      return null;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _useInMemoryMock = true;
      return null;
    }
    try {
      _database ??= await _initDatabase();
      return _database;
    } catch (e) {
      debugPrint("SQLite initialization failed: $e");
      if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
        _useInMemoryMock = true;
        return null;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobilde sessizce in-memory mock'a düşmek yerine hata fırlatıyoruz.
        rethrow;
      }
      _useInMemoryMock = true;
      return null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final pathString = join(dbPath, 'ne_izlesem.db');

    return await openDatabase(
      pathString,
      version: 7,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  Future<void> onCreate(Database db, int version) async {
    // 1. Watchlist Table
    await db.execute('''
      CREATE TABLE watchlist (
        id INTEGER,
        title TEXT NOT NULL,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        vote_average REAL,
        release_date TEXT,
        is_tv INTEGER NOT NULL,
        genre_ids TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, is_tv)
      )
    ''');

    // 2. Ratings Table
    await db.execute('''
      CREATE TABLE ratings (
        movie_id INTEGER,
        is_tv INTEGER NOT NULL,
        rating INTEGER NOT NULL,
        genre_ids TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        vote_average REAL,
        release_date TEXT,
        popularity REAL,
        comment TEXT,
        is_spoiler INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (movie_id, is_tv)
      )
    ''');

    // 3. Search History Table
    await db.execute('''
      CREATE TABLE search_history (
        query TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 4. Watched Seasons Table
    await db.execute('''
      CREATE TABLE watched_seasons (
        tv_id INTEGER NOT NULL,
        season_number INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (tv_id, season_number)
      )
    ''');

    // 5. Favorites Table
    await db.execute('''
      CREATE TABLE favorites (
        id INTEGER,
        title TEXT NOT NULL,
        poster_path TEXT,
        backdrop_path TEXT,
        overview TEXT,
        vote_average REAL,
        release_date TEXT,
        is_tv INTEGER NOT NULL,
        genre_ids TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, is_tv)
      )
    ''');

    // 6. TMDB Cache Table
    await db.execute('''
      CREATE TABLE tmdb_cache (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        locale TEXT NOT NULL
      )
    ''');

    // Indices for updated_at (Performance optimization for delta-sync)
    await db.execute('CREATE INDEX IF NOT EXISTS idx_watchlist_updated_at ON watchlist (updated_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ratings_updated_at ON ratings (updated_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_favorites_updated_at ON favorites (updated_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_watched_seasons_updated_at ON watched_seasons (updated_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_search_history_updated_at ON search_history (updated_at)');
  }

  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE ratings ADD COLUMN title TEXT');
        await db.execute('ALTER TABLE ratings ADD COLUMN poster_path TEXT');
        await db.execute('ALTER TABLE ratings ADD COLUMN backdrop_path TEXT');
        await db.execute('ALTER TABLE ratings ADD COLUMN overview TEXT');
        await db.execute('ALTER TABLE ratings ADD COLUMN vote_average REAL');
        await db.execute('ALTER TABLE ratings ADD COLUMN release_date TEXT');
        await db.execute('ALTER TABLE ratings ADD COLUMN popularity REAL');
      } catch (e) {
        debugPrint("Error migrating database to v2: $e");
      }
    }
    if (oldVersion < 3) {
      try {
        // Migrate watchlist
        await db.execute('ALTER TABLE watchlist RENAME TO watchlist_old;');
        await db.execute('''
          CREATE TABLE watchlist (
            id INTEGER,
            title TEXT NOT NULL,
            poster_path TEXT,
            backdrop_path TEXT,
            overview TEXT,
            vote_average REAL,
            release_date TEXT,
            is_tv INTEGER NOT NULL,
            genre_ids TEXT,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (id, is_tv)
          );
        ''');
        await db.execute('''
          INSERT OR REPLACE INTO watchlist (id, title, poster_path, backdrop_path, overview, vote_average, release_date, is_tv, genre_ids, created_at)
          SELECT id, title, poster_path, backdrop_path, overview, vote_average, release_date, is_tv, genre_ids, created_at
          FROM watchlist_old;
        ''');
        await db.execute('DROP TABLE watchlist_old;');

        // Migrate ratings
        await db.execute('ALTER TABLE ratings RENAME TO ratings_old;');
        await db.execute('''
          CREATE TABLE ratings (
            movie_id INTEGER,
            is_tv INTEGER NOT NULL,
            rating INTEGER NOT NULL,
            genre_ids TEXT,
            created_at INTEGER NOT NULL,
            title TEXT,
            poster_path TEXT,
            backdrop_path TEXT,
            overview TEXT,
            vote_average REAL,
            release_date TEXT,
            popularity REAL,
            PRIMARY KEY (movie_id, is_tv)
          );
        ''');
        await db.execute('''
          INSERT OR REPLACE INTO ratings (movie_id, is_tv, rating, genre_ids, created_at, title, poster_path, backdrop_path, overview, vote_average, release_date, popularity)
          SELECT movie_id, is_tv, rating, genre_ids, created_at, title, poster_path, backdrop_path, overview, vote_average, release_date, popularity
          FROM ratings_old;
        ''');
        await db.execute('DROP TABLE ratings_old;');

        // Migrate favorites
        await db.execute('ALTER TABLE favorites RENAME TO favorites_old;');
        await db.execute('''
          CREATE TABLE favorites (
            id INTEGER,
            title TEXT NOT NULL,
            poster_path TEXT,
            backdrop_path TEXT,
            overview TEXT,
            vote_average REAL,
            release_date TEXT,
            is_tv INTEGER NOT NULL,
            genre_ids TEXT,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (id, is_tv)
          );
        ''');
        await db.execute('''
          INSERT OR REPLACE INTO favorites (id, title, poster_path, backdrop_path, overview, vote_average, release_date, is_tv, genre_ids, created_at)
          SELECT id, title, poster_path, backdrop_path, overview, vote_average, release_date, is_tv, genre_ids, created_at
          FROM favorites_old;
        ''');
        await db.execute('DROP TABLE favorites_old;');
      } catch (e) {
        debugPrint("Error migrating database to v3: $e");
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE watchlist ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE watchlist ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE ratings ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE ratings ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE favorites ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE favorites ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE watched_seasons ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE watched_seasons ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE search_history ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'ALTER TABLE search_history ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint("Error migrating database to v4: $e");
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE ratings ADD COLUMN comment TEXT');
        await db.execute(
          'ALTER TABLE ratings ADD COLUMN is_spoiler INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint("Error migrating database to v5: $e");
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE tmdb_cache (
            cache_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            fetched_at INTEGER NOT NULL,
            locale TEXT NOT NULL
          )
        ''');
      } catch (e) {
        debugPrint("Error migrating database to v6: $e");
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_watchlist_updated_at ON watchlist (updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ratings_updated_at ON ratings (updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_favorites_updated_at ON favorites (updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_watched_seasons_updated_at ON watched_seasons (updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_search_history_updated_at ON search_history (updated_at)');
      } catch (e) {
        debugPrint("Error migrating database to v7 (adding indices): $e");
      }
    }
  }

  // ─── Ratings Operations ──────────────────────────────────────────────────────

  Future<void> saveRating({
    Movie? movie,
    int? movieId,
    bool? isTV,
    required int rating,
    List<int>? genreIds,
    int? updatedAt,
    int? deleted,
    String? comment,
    int? isSpoiler,
  }) async {
    final db = await database;
    final finalMovieId = movieId ?? movie?.id ?? 0;
    final finalIsTV = isTV ?? movie?.isTV ?? false;
    final finalGenreIds = genreIds ?? movie?.genreIds ?? const <int>[];
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final delVal = deleted ?? 0;

    if (db == null) {
      _mockRatings.removeWhere(
        (e) =>
            e['movie_id'] == finalMovieId && e['is_tv'] == (finalIsTV ? 1 : 0),
      );
      _mockRatings.add({
        'movie_id': finalMovieId,
        'is_tv': finalIsTV ? 1 : 0,
        'rating': rating,
        'genre_ids': jsonEncode(finalGenreIds),
        'created_at': now,
        'updated_at': now,
        'deleted': delVal,
        'title': movie?.title ?? '',
        'poster_path': movie?.posterPath,
        'backdrop_path': movie?.backdropPath,
        'overview': movie?.overview ?? '',
        'vote_average': movie?.voteAverage ?? 0.0,
        'release_date': movie?.releaseDate,
        'popularity': movie?.popularity ?? 0.0,
        'comment': comment,
        'is_spoiler': isSpoiler ?? 0,
      });
      return;
    }
    await db.insert('ratings', {
      'movie_id': finalMovieId,
      'is_tv': finalIsTV ? 1 : 0,
      'rating': rating,
      'genre_ids': jsonEncode(finalGenreIds),
      'created_at': now,
      'updated_at': now,
      'deleted': delVal,
      'title': movie?.title ?? '',
      'poster_path': movie?.posterPath,
      'backdrop_path': movie?.backdropPath,
      'overview': movie?.overview ?? '',
      'vote_average': movie?.voteAverage ?? 0.0,
      'release_date': movie?.releaseDate,
      'popularity': movie?.popularity ?? 0.0,
      'comment': comment,
      'is_spoiler': isSpoiler ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getRating(int movieId, bool isTV) async {
    final db = await database;
    if (db == null) {
      final match = _mockRatings.firstWhere(
        (e) => e['movie_id'] == movieId && e['is_tv'] == (isTV ? 1 : 0),
        orElse: () => <String, dynamic>{},
      );
      return match.isNotEmpty ? match : null;
    }
    final maps = await db.query(
      'ratings',
      where: 'movie_id = ? AND is_tv = ? AND deleted = 0',
      whereArgs: [movieId, isTV ? 1 : 0],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getRatings() async {
    final db = await database;
    if (db == null) {
      final sorted = List<Map<String, dynamic>>.from(_mockRatings)
        ..sort(
          (a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int),
        );
      return sorted.where((m) => m['deleted'] != 1).map((m) {
        final genreIdsList =
            (jsonDecode(m['genre_ids'] as String) as List<dynamic>)
                .map((e) => e as int)
                .toList();
        return {
          'id': m['movie_id'] as int,
          'isTV': (m['is_tv'] as int) == 1,
          'rating': m['rating'] as int,
          'genreIds': genreIdsList,
          'created_at': m['created_at'] as int,
          'movie': Movie(
            id: m['movie_id'] as int,
            title: m['title'] as String? ?? '',
            posterPath: m['poster_path'] as String?,
            backdropPath: m['backdrop_path'] as String?,
            overview: m['overview'] as String? ?? '',
            voteAverage: (m['vote_average'] as num? ?? 0).toDouble(),
            releaseDate: m['release_date'] as String?,
            isTV: (m['is_tv'] as int) == 1,
            genreIds: genreIdsList,
            popularity: (m['popularity'] as num? ?? 0).toDouble(),
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
      final genreIdsList =
          (jsonDecode(m['genre_ids'] as String) as List<dynamic>)
              .map((e) => e as int)
              .toList();
      return {
        'id': m['movie_id'] as int,
        'isTV': (m['is_tv'] as int) == 1,
        'rating': m['rating'] as int,
        'genreIds': genreIdsList,
        'created_at': m['created_at'] as int,
        'movie': Movie(
          id: m['movie_id'] as int,
          title: m['title'] as String? ?? '',
          posterPath: m['poster_path'] as String?,
          backdropPath: m['backdrop_path'] as String?,
          overview: m['overview'] as String? ?? '',
          voteAverage: (m['vote_average'] as num? ?? 0).toDouble(),
          releaseDate: m['release_date'] as String?,
          isTV: (m['is_tv'] as int) == 1,
          genreIds: genreIdsList,
          popularity: (m['popularity'] as num? ?? 0).toDouble(),
        ),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getRatingsForWeights() async {
    final db = await database;
    if (db == null) {
      return _mockRatings
          .where((m) => m['deleted'] != 1)
          .map((m) => {
                'id': m['movie_id'] as int,
                'isTV': (m['is_tv'] as int) == 1,
                'rating': m['rating'] as int,
                'genreIds': (jsonDecode(m['genre_ids'] as String) as List<dynamic>)
                    .map((e) => e as int)
                    .toList(),
                'created_at': m['created_at'] as int,
              })
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'ratings',
      columns: ['movie_id', 'is_tv', 'rating', 'genre_ids', 'created_at'],
      where: 'deleted = 0',
    );
    return maps.map((m) {
      final genreIdsList =
          (jsonDecode(m['genre_ids'] as String) as List<dynamic>)
              .map((e) => e as int)
              .toList();
      return {
        'id': m['movie_id'] as int,
        'isTV': (m['is_tv'] as int) == 1,
        'rating': m['rating'] as int,
        'genreIds': genreIdsList,
        'created_at': m['created_at'] as int,
      };
    }).toList();
  }

  Future<Set<String>> getRatedIds() async {
    final db = await database;
    if (db == null) {
      return _mockRatings
          .where((m) => m['deleted'] != 1)
          .map(
            (m) =>
                "${(m['is_tv'] as int) == 1 ? 'tv' : 'movie'}_${m['movie_id']}",
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
              "${(m['is_tv'] as int) == 1 ? 'tv' : 'movie'}_${m['movie_id']}",
        )
        .toSet();
  }

  Future<void> deleteRating(int movieId, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final idx = _mockRatings.indexWhere(
        (e) => e['movie_id'] == movieId && e['is_tv'] == (isTV ? 1 : 0),
      );
      if (idx >= 0) {
        _mockRatings[idx]['deleted'] = 1;
        _mockRatings[idx]['updated_at'] = now;
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

  Future<int> getRatingCount() async {
    final db = await database;
    if (db == null) {
      return _mockRatings.where((e) => e['deleted'] != 1).length;
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ratings WHERE deleted = 0'),
    );
    return count ?? 0;
  }

  // ─── Watchlist Operations ────────────────────────────────────────────────────

  Future<void> addToWatchlist(
    Movie movie, {
    int? updatedAt,
    int? deleted,
  }) async {
    final db = await database;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final delVal = deleted ?? 0;
    if (db == null) {
      _mockWatchlist.removeWhere(
        (e) => e['id'] == movie.id && e['is_tv'] == (movie.isTV ? 1 : 0),
      );
      _mockWatchlist.add({
        'id': movie.id,
        'title': movie.title,
        'poster_path': movie.posterPath,
        'backdrop_path': movie.backdropPath,
        'overview': movie.overview,
        'vote_average': movie.voteAverage,
        'release_date': movie.releaseDate,
        'is_tv': movie.isTV ? 1 : 0,
        'genre_ids': jsonEncode(movie.genreIds),
        'created_at': now,
        'updated_at': now,
        'deleted': delVal,
      });
      return;
    }
    await db.insert('watchlist', {
      'id': movie.id,
      'title': movie.title,
      'poster_path': movie.posterPath,
      'backdrop_path': movie.backdropPath,
      'overview': movie.overview,
      'vote_average': movie.voteAverage,
      'release_date': movie.releaseDate,
      'is_tv': movie.isTV ? 1 : 0,
      'genre_ids': jsonEncode(movie.genreIds),
      'created_at': now,
      'updated_at': now,
      'deleted': delVal,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFromWatchlist(int id, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final idx = _mockWatchlist.indexWhere(
        (e) => e['id'] == id && e['is_tv'] == (isTV ? 1 : 0),
      );
      if (idx >= 0) {
        _mockWatchlist[idx]['deleted'] = 1;
        _mockWatchlist[idx]['updated_at'] = now;
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
      return _mockWatchlist.any(
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
      final sorted = List<Map<String, dynamic>>.from(_mockWatchlist)
        ..sort(
          (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
        ); // newest first
      return sorted
          .where((m) => m['deleted'] != 1)
          .map(
            (m) => Movie.fromStorage({
              'id': m['id'] as int,
              'title': m['title'] as String,
              'poster_path': m['poster_path'] as String?,
              'backdrop_path': m['backdrop_path'] as String?,
              'overview': m['overview'] as String,
              'vote_average': m['vote_average'] as double,
              'release_date': m['release_date'] as String?,
              'isTV': (m['is_tv'] as int) == 1,
              'genre_ids':
                  jsonDecode(m['genre_ids'] as String) as List<dynamic>,
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
            'id': m['id'] as int,
            'title': m['title'] as String,
            'poster_path': m['poster_path'] as String?,
            'backdrop_path': m['backdrop_path'] as String?,
            'overview': m['overview'] as String,
            'vote_average': m['vote_average'] as double,
            'release_date': m['release_date'] as String?,
            'isTV': (m['is_tv'] as int) == 1,
            'genre_ids': jsonDecode(m['genre_ids'] as String) as List<dynamic>,
          }),
        )
        .toList();
  }

  // ─── Search History Operations ────────────────────────────────────────────────

  Future<void> addSearchHistory(String query) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      _mockSearchHistory.removeWhere((e) => e['query'] == query);
      _mockSearchHistory.add({
        'query': query,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      });
      _mockSearchHistory.sort(
        (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
      );
      if (_mockSearchHistory.length > 10) {
        _mockSearchHistory.removeRange(10, _mockSearchHistory.length);
      }
      return;
    }
    await db.insert('search_history', {
      'query': query,
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
      return _mockSearchHistory
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
      for (final e in _mockSearchHistory) {
        e['deleted'] = 1;
        e['updated_at'] = now;
      }
      return;
    }
    await db.update('search_history', {'deleted': 1, 'updated_at': now});
  }

  // ─── Watched Seasons Operations ────────────────────────────────────────────────

  Future<void> toggleSeason(
    int tvId,
    int seasonNumber, {
    int? updatedAt,
    int? deleted,
  }) async {
    final db = await database;
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      final index = _mockWatchedSeasons.indexWhere(
        (e) => e['tv_id'] == tvId && e['season_number'] == seasonNumber,
      );
      if (index >= 0) {
        if (deleted == null) {
          // Normal toggle behavior (remove if exist)
          _mockWatchedSeasons.removeAt(index);
        } else {
          _mockWatchedSeasons[index]['deleted'] = deleted;
          _mockWatchedSeasons[index]['updated_at'] = now;
        }
      } else {
        _mockWatchedSeasons.add({
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
      return _mockWatchedSeasons
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

  // ─── Favorites Operations ────────────────────────────────────────────────────

  Future<void> saveFavorites(List<Movie> items, bool isTV) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      _mockFavorites.removeWhere((e) => e['is_tv'] == (isTV ? 1 : 0));
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _mockFavorites.add({
          'id': item.id,
          'title': item.title,
          'poster_path': item.posterPath,
          'backdrop_path': item.backdropPath,
          'overview': item.overview,
          'vote_average': item.voteAverage,
          'release_date': item.releaseDate,
          'is_tv': isTV ? 1 : 0,
          'genre_ids': jsonEncode(item.genreIds),
          'created_at': i,
          'updated_at': now,
          'deleted': 0,
        });
      }
      return;
    }
    await db.transaction((txn) async {
      await txn.update(
        'favorites',
        {'deleted': 1, 'updated_at': now},
        where: 'is_tv = ?',
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
          _mockFavorites
              .where((e) => e['is_tv'] == (isTV ? 1 : 0) && e['deleted'] != 1)
              .toList()
            ..sort(
              (a, b) =>
                  (a['created_at'] as int).compareTo(b['created_at'] as int),
            );
      return filtered
          .map(
            (m) => Movie.fromStorage({
              'id': m['id'] as int,
              'title': m['title'] as String,
              'poster_path': m['poster_path'] as String?,
              'backdrop_path': m['backdrop_path'] as String?,
              'overview': m['overview'] as String,
              'vote_average': m['vote_average'] as double,
              'release_date': m['release_date'] as String?,
              'isTV': (m['is_tv'] as int) == 1,
              'genre_ids':
                  jsonDecode(m['genre_ids'] as String) as List<dynamic>,
            }),
          )
          .toList();
    }
    final List<Map<String, dynamic>> maps = await db.query(
      'favorites',
      where: 'is_tv = ? AND deleted = 0',
      whereArgs: [isTV ? 1 : 0],
      orderBy: 'created_at ASC',
    );
    return maps
        .map(
          (m) => Movie.fromStorage({
            'id': m['id'] as int,
            'title': m['title'] as String,
            'poster_path': m['poster_path'] as String?,
            'backdrop_path': m['backdrop_path'] as String?,
            'overview': m['overview'] as String,
            'vote_average': m['vote_average'] as double,
            'release_date': m['release_date'] as String?,
            'isTV': (m['is_tv'] as int) == 1,
            'genre_ids': jsonDecode(m['genre_ids'] as String) as List<dynamic>,
          }),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> getFavoritesRaw() async {
    final db = await database;
    if (db == null) {
      return _mockFavorites.where((e) => e['deleted'] != 1).toList();
    }
    return await db.query(
      'favorites',
      columns: ['genre_ids', 'created_at'],
      where: 'deleted = 0',
    );
  }

  // ─── Clear / Reset ───────────────────────────────────────────────────────────

  // Soft delete all data to trigger sync deletions to remote server
  Future<void> softClearAllData() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db == null) {
      for (final list in [
        _mockWatchlist,
        _mockRatings,
        _mockSearchHistory,
        _mockWatchedSeasons,
        _mockFavorites,
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

  // Hard delete all data (on logout / fresh clean)
  Future<void> hardClearAllData() async {
    final db = await database;
    if (db == null) {
      _mockWatchlist.clear();
      _mockRatings.clear();
      _mockSearchHistory.clear();
      _mockWatchedSeasons.clear();
      _mockFavorites.clear();
      _mockTmdbCache.clear();
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

  // ─── TMDB Cache Operations ──────────────────────────────────────────────────

  Future<void> saveTmdbCache(String key, String payload, String locale) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    if (db == null) {
      _mockTmdbCache.removeWhere((e) => e['cache_key'] == key);
      _mockTmdbCache.add({
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
      final matches = _mockTmdbCache.where((e) => e['cache_key'] == key);
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
      _mockTmdbCache.removeWhere((e) => e['fetched_at'] < expiryLimit);
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
      _mockTmdbCache.clear();
      return;
    }
    await db.delete('tmdb_cache');
  }

  // Anahtarlar artık sürüm önekiyle başladığı için ("v2:/3/...") yol eşleşmesi
  // startsWith değil contains ile yapılır (bkz. TmdbService._cacheKey).
  Future<void> deleteTmdbCachePaths(List<String> prefixes) async {
    final db = await database;
    if (db == null) {
      _mockTmdbCache.removeWhere((e) {
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
      _mockTmdbCache.removeWhere(
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
      _mockTmdbCache.removeWhere((e) {
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
