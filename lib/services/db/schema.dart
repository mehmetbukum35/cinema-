part of '../db_helper.dart';

mixin DbSchemaMixin {
  /// Migration'larla eklenen kolonların kanonik tanımı; `onCreate` ile bire bir
  /// uyumlu olmalıdır.
  ///
  /// `ensureSchema` eksik kalan kolonları buradan tamamlar. Taban (v1) kolonları
  /// her sürümde var olduğu için listeye dahil değildir.
  static const Map<String, Map<String, String>> _migratedColumns = {
    'watchlist': {
      'metadata_locale': "TEXT NOT NULL DEFAULT 'und'",
      'updated_at': 'INTEGER NOT NULL DEFAULT 0',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
    },
    'ratings': {
      'title': 'TEXT',
      'poster_path': 'TEXT',
      'backdrop_path': 'TEXT',
      'overview': 'TEXT',
      'vote_average': 'REAL',
      'release_date': 'TEXT',
      'popularity': 'REAL',
      'metadata_locale': "TEXT NOT NULL DEFAULT 'und'",
      'updated_at': 'INTEGER NOT NULL DEFAULT 0',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
      'comment': 'TEXT',
      'is_spoiler': 'INTEGER NOT NULL DEFAULT 0',
      'is_private': 'INTEGER NOT NULL DEFAULT 0',
      'original_language': 'TEXT',
      'origin_countries': 'TEXT',
    },
    'favorites': {
      'metadata_locale': "TEXT NOT NULL DEFAULT 'und'",
      'updated_at': 'INTEGER NOT NULL DEFAULT 0',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
    },
    'search_history': {
      'updated_at': 'INTEGER NOT NULL DEFAULT 0',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
    },
    'watched_seasons': {
      'updated_at': 'INTEGER NOT NULL DEFAULT 0',
      'deleted': 'INTEGER NOT NULL DEFAULT 0',
    },
  };

  static const String _tmdbCacheDdl = '''
      CREATE TABLE IF NOT EXISTS tmdb_cache (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        locale TEXT NOT NULL
      )
    ''';

  /// Delta-sync indeksleri: indeks adı → tablo.
  static const Map<String, String> _deltaSyncIndices = {
    'idx_watchlist_updated_at': 'watchlist',
    'idx_ratings_updated_at': 'ratings',
    'idx_favorites_updated_at': 'favorites',
    'idx_watched_seasons_updated_at': 'watched_seasons',
    'idx_search_history_updated_at': 'search_history',
  };

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<Set<String>> _columnsOf(
    DatabaseExecutor db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  /// Kolon yoksa ekler, varsa dokunmaz.
  ///
  /// Tekrar çalıştırılabilir olması kritik: yarım kalmış bir migration ikinci
  /// denemede "duplicate column" hatasıyla patlayıp kalan adımları atlamaz.
  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if (!await _tableExists(db, table)) return;
    if ((await _columnsOf(db, table)).contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<void> _addColumnsIfMissing(
    DatabaseExecutor db,
    String table,
    Map<String, String> columns,
  ) async {
    for (final entry in columns.entries) {
      await _addColumnIfMissing(db, table, entry.key, entry.value);
    }
  }

  /// Şemayı kanonik tanımla karşılaştırıp eksikleri tamamlar.
  ///
  /// Sürüm numarası yükseltilmiş ama kolonları eksik kalmış cihazları kurtarır:
  /// eski migration kodu hataları yuttuğu için bazı kurulumlarda şema yarım
  /// kalmış olabilir ve `onUpgrade` o cihazlarda bir daha çalışmaz.
  Future<void> ensureSchema(Database db) async {
    await db.execute('PRAGMA busy_timeout = 3000;');
    await db.execute(_tmdbCacheDdl);
    for (final table in _migratedColumns.keys) {
      await _addColumnsIfMissing(db, table, _migratedColumns[table]!);
    }
    for (final entry in _deltaSyncIndices.entries) {
      if (!await _tableExists(db, entry.value)) continue;
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${entry.key} ON ${entry.value} (updated_at)',
      );
    }
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
        metadata_locale TEXT NOT NULL DEFAULT 'und',
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
        metadata_locale TEXT NOT NULL DEFAULT 'und',
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
        is_private INTEGER NOT NULL DEFAULT 0,
        original_language TEXT,
        origin_countries TEXT,
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
        metadata_locale TEXT NOT NULL DEFAULT 'und',
        genre_ids TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, is_tv)
      )
    ''');

    // 6. TMDB Cache Table
    await db.execute(_tmdbCacheDdl);

    // Indices for updated_at (Performance optimization for delta-sync)
    for (final entry in _deltaSyncIndices.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${entry.key} ON ${entry.value} (updated_at)',
      );
    }
  }

  /// Şemayı `oldVersion`'dan güncel sürüme taşır.
  ///
  /// Adımlar bilerek try/catch ile sarılmamıştır. sqflite `onUpgrade`'i bir
  /// transaction içinde çalıştırdığı için, fırlatılan bir hata tüm değişiklikleri
  /// geri alır ve sürüm numarasını yükseltmez; migration bir sonraki açılışta
  /// baştan denenir. Hatayı yutmak ise yarım uygulanmış şemayı "tamamlandı" diye
  /// kaydeder ve cihazı kalıcı olarak bozuk bırakır. Her adım ayrıca tekrar
  /// çalıştırılabilir (idempotent) tutulmuştur.
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnsIfMissing(db, 'ratings', const {
        'title': 'TEXT',
        'poster_path': 'TEXT',
        'backdrop_path': 'TEXT',
        'overview': 'TEXT',
        'vote_average': 'REAL',
        'release_date': 'TEXT',
        'popularity': 'REAL',
      });
    }
    if (oldVersion < 3) {
      {
        // Tabloları yeni birincil anahtara (id, is_tv) taşımak için yeniden kur.
        // `*_old` artıkları yalnızca yarıda kesilmiş bir denemeden kalabilir;
        // transaction geri alma sayesinde bu durum pratikte oluşmaz, ama kalırsa
        // rename adımını kalıcı olarak kilitlememesi için temizleniyor.
        await db.execute('DROP TABLE IF EXISTS watchlist_old;');
        await db.execute('DROP TABLE IF EXISTS ratings_old;');
        await db.execute('DROP TABLE IF EXISTS favorites_old;');

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
      }
    }
    if (oldVersion < 4) {
      const syncColumns = {
        'updated_at': 'INTEGER NOT NULL DEFAULT 0',
        'deleted': 'INTEGER NOT NULL DEFAULT 0',
      };
      for (final table in const [
        'watchlist',
        'ratings',
        'favorites',
        'watched_seasons',
        'search_history',
      ]) {
        await _addColumnsIfMissing(db, table, syncColumns);
      }
    }
    if (oldVersion < 5) {
      await _addColumnsIfMissing(db, 'ratings', const {
        'comment': 'TEXT',
        'is_spoiler': 'INTEGER NOT NULL DEFAULT 0',
      });
    }
    if (oldVersion < 6) {
      await db.execute(_tmdbCacheDdl);
    }
    if (oldVersion < 7) {
      for (final entry in _deltaSyncIndices.entries) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS ${entry.key} ON ${entry.value} (updated_at)',
        );
      }
    }
    if (oldVersion < 8) {
      await _addColumnIfMissing(
        db,
        'ratings',
        'is_private',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 9) {
      for (final table in const ['ratings', 'watchlist', 'favorites']) {
        await _addColumnIfMissing(
          db,
          table,
          'metadata_locale',
          "TEXT NOT NULL DEFAULT 'und'",
        );
      }
    }
    if (oldVersion < 10) {
      await _addColumnsIfMissing(db, 'ratings', const {
        'original_language': 'TEXT',
        'origin_countries': 'TEXT',
      });
    }
  }
}
