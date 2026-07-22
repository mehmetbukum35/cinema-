import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

// Simple mock for ApiService
class MockApiService implements ApiService {
  Map<String, dynamic>? pushedPayload;
  final List<Map<String, dynamic>> pushedPayloads = [];
  int? pulledSince;
  Map<String, dynamic> pullResponse = {};
  Map<String, dynamic> pushResponse = {'applied': 0};
  bool shouldThrow = false;
  bool throwOnPull = false;
  bool resetRequiredOnFirstPush = false;
  int pushCount = 0;
  int pullCount = 0;
  Duration? delay;
  Completer<void>? pushStarted;
  Completer<void>? pushGate;

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushCount++;
    pushStarted?.complete();
    if (pushGate case final gate?) await gate.future;
    pushedPayload = payload;
    pushedPayloads.add(payload);
    if (resetRequiredOnFirstPush && pushCount == 1) {
      throw ApiException(
        statusCode: 409,
        message: 'Full resync required',
        code: 'sync_reset_required',
      );
    }
    if (delay != null) await Future.delayed(delay!);
    if (shouldThrow) throw Exception('API Error');
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> pull(
    int since, {
    bool localReset = false,
  }) async {
    pullCount++;
    pulledSince = since;
    if (delay != null) await Future.delayed(delay!);
    if (shouldThrow || throwOnPull) throw Exception('API Error');
    return pullResponse;
  }

  // Define other required methods to satisfy ApiService interface
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Initialize FFI for SQLite tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late MockApiService mockApi;
  late SyncService syncService;

  setUp(() async {
    // 1. Initialize Mock SharedPreferences
    SharedPreferences.setMockInitialValues({'sync_last_time': 1000});
    PrefsService.activeLanguageCode = 'tr';

    // 2. Open Fresh In-Memory Test SQLite Database
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 9,
      onCreate: DatabaseHelper().onCreate,
      onUpgrade: DatabaseHelper().onUpgrade,
    );

    // 3. Inject Test DB into DatabaseHelper
    DatabaseHelper.databaseInstance = testDb;

    // 4. Initialize Services
    mockApi = MockApiService();
    syncService = SyncService(mockApi);
  });

  tearDown(() async {
    await testDb.close();
    DatabaseHelper.databaseInstance = null;
  });

  group('SyncService Tests', () {
    test('should push local changes correctly', () async {
      // 1. Arrange: Insert a local rating and a local watchlist entry updated after last_sync (1000)
      await testDb.insert('ratings', {
        'movie_id': 123,
        'is_tv': 0,
        'rating': 3,
        'genre_ids': jsonEncode([28, 35]),
        'title': 'Test Movie',
        'poster_path': '/path.jpg',
        'backdrop_path': '/back.jpg',
        'overview': 'Overview...',
        'vote_average': 8.5,
        'release_date': '2026-01-01',
        'popularity': 120.0,
        'created_at': 1005,
        'updated_at': 1010, // > 1000 lastSync
        'deleted': 0,
      });

      await testDb.insert('watchlist', {
        'id': 456,
        'is_tv': 1,
        'title': 'Test Show',
        'poster_path': '/show.jpg',
        'backdrop_path': '/backshow.jpg',
        'overview': 'Show overview...',
        'vote_average': 7.9,
        'release_date': '2026-02-01',
        'genre_ids': jsonEncode([18]),
        'created_at': 1006,
        'updated_at': 1015, // > 1000 lastSync
        'deleted': 1, // Soft deleted
      });

      // Mock empty pull response
      mockApi.pullResponse = {
        'server_time': 1100,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      // 2. Act: Run Sync
      await syncService.sync();

      // 3. Assert: Verify the push payload contained correct fields
      expect(mockApi.pushedPayload, isNotNull);
      expect(mockApi.pushedPayload!['metadata_locale'], 'tr');
      final ratingsPayload = mockApi.pushedPayload!['ratings'] as List<dynamic>;
      expect(ratingsPayload, hasLength(1));
      expect(ratingsPayload[0]['movie_id'], 123);
      expect(ratingsPayload[0]['rating'], 3);
      expect(ratingsPayload[0]['deleted'], false);
      expect(ratingsPayload[0]['metadata_locale'], 'und');

      final watchlistPayload =
          mockApi.pushedPayload!['watchlist'] as List<dynamic>;
      expect(watchlistPayload, hasLength(1));
      expect(watchlistPayload[0]['id'], 456);
      expect(watchlistPayload[0]['deleted'], true);
      expect(watchlistPayload[0]['metadata_locale'], 'und');

      // One millisecond overlap prevents equal-watermark writes being skipped.
      expect(await PrefsService.getLastSyncTime(), 1099);
    });

    test('should tolerate null genre metadata in legacy rows', () async {
      await testDb.insert('ratings', {
        'movie_id': 321,
        'is_tv': 0,
        'rating': 4,
        'genre_ids': null,
        'created_at': 1001,
        'updated_at': 1002,
        'deleted': 0,
      });
      mockApi.pullResponse = {
        'server_time': 1100,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      await syncService.sync();

      final ratings = mockApi.pushedPayload!['ratings'] as List<dynamic>;
      expect(ratings.single['genre_ids'], isEmpty);
    });

    test('should split large pushes into 500-row batches', () async {
      final batch = testDb.batch();
      for (var i = 0; i < 501; i++) {
        batch.insert('ratings', {
          'movie_id': 10000 + i,
          'is_tv': 0,
          'rating': 3,
          'genre_ids': '[]',
          'created_at': 1001,
          'updated_at': 1002 + i,
          'deleted': 0,
        });
      }
      await batch.commit(noResult: true);
      mockApi.pullResponse = {
        'server_time': 2000,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      await syncService.sync();

      expect(mockApi.pushCount, 2);
      expect(mockApi.pushedPayloads[0]['ratings'], hasLength(500));
      expect(mockApi.pushedPayloads[1]['ratings'], hasLength(1));
    });

    test('should pull remote changes and apply them locally', () async {
      // 1. Arrange: Setup remote changes in Pull Response
      mockApi.pullResponse = {
        'server_time': 2000,
        'ratings': [
          {
            'movie_id': 789,
            'is_tv': 0,
            'metadata_locale': 'en',
            'rating': 2,
            'genre_ids': [12, 14],
            'title': 'Remote Movie',
            'poster_path': '/remote.jpg',
            'backdrop_path': '/remote_back.jpg',
            'overview': 'Remote overview',
            'vote_average': 6.8,
            'release_date': '2026-03-01',
            'popularity': 45.0,
            'created_at': 1500,
            'updated_at': 1600,
            'deleted': false,
          },
        ],
        'watchlist': [
          {
            'id': 999,
            'is_tv': 1,
            'metadata_locale': 'en',
            // Catalog metadata may be absent after tombstone compaction.
            'title': null,
            'poster_path': '/show.jpg',
            'backdrop_path': '/show_back.jpg',
            'overview': 'Show overview',
            'vote_average': 8.0,
            'release_date': '2026-04-01',
            'genre_ids': [18, 53],
            'created_at': 1501,
            'updated_at': 1700,
            'deleted': true, // Remote soft delete
          },
        ],
        'favorites': [
          {
            'id': 1000,
            'is_tv': 0,
            'metadata_locale': 'en',
            'title': null,
            'poster_path': null,
            'backdrop_path': null,
            'overview': null,
            'vote_average': null,
            'release_date': null,
            'genre_ids': null,
            'created_at': 1502,
            'updated_at': 1800,
            'deleted': true,
          },
        ],
        'watched_seasons': [],
        'search_history': [],
      };

      // 2. Act: Run Sync
      await syncService.sync();

      // 3. Assert: Verify pull was queried with since=1000 (initial sync time)
      expect(mockApi.pulledSince, 1000);

      // Verify rating was inserted locally
      final dbRatings = await testDb.query(
        'ratings',
        where: 'movie_id = ?',
        whereArgs: [789],
      );
      expect(dbRatings, hasLength(1));
      expect(dbRatings[0]['rating'], 2);
      expect(dbRatings[0]['title'], 'Remote Movie');
      expect(dbRatings[0]['metadata_locale'], 'en');
      expect(jsonDecode(dbRatings[0]['genre_ids'] as String), [12, 14]);

      // Verify watchlist soft-delete was applied locally
      final dbWatchlist = await testDb.query(
        'watchlist',
        where: 'id = ?',
        whereArgs: [999],
      );
      expect(dbWatchlist, hasLength(1));
      expect(dbWatchlist[0]['deleted'], 1);
      expect(dbWatchlist[0]['metadata_locale'], 'en');
      expect(dbWatchlist[0]['title'], '');

      final dbFavorites = await testDb.query(
        'favorites',
        where: 'id = ?',
        whereArgs: [1000],
      );
      expect(dbFavorites, hasLength(1));
      expect(dbFavorites[0]['deleted'], 1);
      expect(dbFavorites[0]['title'], '');

      expect(await PrefsService.getLastSyncTime(), 1999);
    });

    test('should coalesce multiple concurrent sync requests', () async {
      mockApi.delay = const Duration(milliseconds: 50);
      mockApi.pullResponse = {
        'server_time': 3000,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      final f1 = syncService.sync();
      final f2 = syncService.sync();

      await Future.wait([f1, f2]);

      expect(mockApi.pushCount, 1);
      expect(mockApi.pullCount, 1);
    });

    test('should cancel stale sync when authenticated user changes', () async {
      await PrefsService.saveUserData({'id': 1, 'email': 'one@example.com'});
      mockApi.pushStarted = Completer<void>();
      mockApi.pushGate = Completer<void>();
      mockApi.pullResponse = {
        'server_time': 3000,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      final pendingSync = syncService.sync();
      await mockApi.pushStarted!.future;
      await PrefsService.saveUserData({'id': 2, 'email': 'two@example.com'});
      mockApi.pushGate!.complete();
      await pendingSync;

      expect(mockApi.pushCount, 1);
      expect(mockApi.pullCount, 0);
      expect(await PrefsService.getLastSyncTime(), 1000);
    });

    test(
      'replays only the watermark row when the following pull fails',
      () async {
        await testDb.insert('search_history', {
          'query': 'arrival',
          'created_at': 1005,
          'updated_at': 1010,
          'deleted': 0,
        });
        mockApi.throwOnPull = true;

        await expectLater(syncService.sync(), throwsException);
        expect(mockApi.pushedPayload!['search_history'], hasLength(1));

        mockApi.throwOnPull = false;
        mockApi.pullResponse = {
          'server_time': 2000,
          'ratings': [],
          'watchlist': [],
          'favorites': [],
          'watched_seasons': [],
          'search_history': [],
        };
        await syncService.sync();

        expect(mockApi.pushCount, 2);
        expect(mockApi.pushedPayload!['search_history'], hasLength(1));
        expect(mockApi.pushedPayload!['search_history'][0]['query'], 'arrival');
      },
    );

    test(
      'should sync all tables (favorites, watched_seasons, search_history)',
      () async {
        // 1. Arrange local data
        await testDb.insert('favorites', {
          'id': 111,
          'is_tv': 0,
          'title': 'Fav Movie',
          'poster_path': '/fav.jpg',
          'backdrop_path': '/fav_back.jpg',
          'overview': 'Fav overview',
          'vote_average': 9.0,
          'release_date': '2026-05-01',
          'genre_ids': jsonEncode([28]),
          'created_at': 1005,
          'updated_at': 1020, // > lastPush (1000)
          'deleted': 0,
        });

        await testDb.insert('watched_seasons', {
          'tv_id': 222,
          'season_number': 2,
          'updated_at': 1030, // > lastPush (1000)
          'deleted': 0,
        });

        await testDb.insert('search_history', {
          'query': 'inception',
          'created_at': 1005,
          'updated_at': 1040, // > lastPush (1000)
          'deleted': 0,
        });

        // Mock remote pull data
        mockApi.pullResponse = {
          'server_time': 3000,
          'ratings': [],
          'watchlist': [],
          'favorites': [
            {
              'id': 333,
              'is_tv': 0,
              'title': 'Remote Fav',
              'poster_path': '/rf.jpg',
              'backdrop_path': '/rfb.jpg',
              'overview': 'Remote fav desc',
              'vote_average': 8.2,
              'release_date': '2026-06-01',
              'genre_ids': [18],
              'created_at': 1500,
              'updated_at': 1600,
              'deleted': false,
            },
          ],
          'watched_seasons': [
            {
              'tv_id': 444,
              'season_number': 1,
              'updated_at': 1700,
              'deleted': false,
            },
          ],
          'search_history': [
            {
              'query': 'interstellar',
              'created_at': 1500,
              'updated_at': 1800,
              'deleted': false,
            },
          ],
        };

        // 2. Act
        await syncService.sync();

        // 3. Assert Pushed data (first push = local outbound; a follow-up may
        // push remapped favorites ranks after normalizeFavoritesCap).
        expect(mockApi.pushedPayloads, isNotEmpty);
        final firstPush = mockApi.pushedPayloads.first;
        final favsPushed = firstPush['favorites'] as List;
        expect(favsPushed, hasLength(1));
        expect(favsPushed[0]['id'], 111);

        final seasonsPushed = firstPush['watched_seasons'] as List;
        expect(seasonsPushed, hasLength(1));
        expect(seasonsPushed[0]['tv_id'], 222);

        final searchPushed = firstPush['search_history'] as List;
        expect(searchPushed, hasLength(1));
        expect(searchPushed[0]['query'], 'inception');

        // 4. Assert Pulled data is written to DB
        final dbFavs = await testDb.query('favorites', where: 'id = 333');
        expect(dbFavs, hasLength(1));
        expect(dbFavs[0]['title'], 'Remote Fav');

        final dbSeasons = await testDb.query(
          'watched_seasons',
          where: 'tv_id = 444',
        );
        expect(dbSeasons, hasLength(1));
        expect(dbSeasons[0]['season_number'], 1);

        final dbSearch = await testDb.query(
          'search_history',
          where: 'query = ?',
          whereArgs: ['interstellar'],
        );
        expect(dbSearch, hasLength(1));
        expect(dbSearch[0]['deleted'], 0);
      },
    );

    test(
      'should propagate errors and allow SyncNotifier to update state accordingly',
      () async {
        mockApi.shouldThrow = true;
        final notifier = SyncNotifier(syncService);

        expect(notifier.state, SyncStatus.idle);

        try {
          await notifier.performSync();
          fail('Should have thrown an exception');
        } catch (e) {
          expect(notifier.state, SyncStatus.error);
        }
      },
    );

    test(
      'should handle device time behind server time using dual watermark',
      () async {
        // 1. Arrange: Device time is behind server time.
        // We simulate this by letting the server return a timestamp far in the future (e.g. +10 days),
        // while device writes use the actual current device time.
        await PrefsService.setLastSyncTime(0);
        await PrefsService.setLastPushTime(0);

        final now = DateTime.now().millisecondsSinceEpoch;
        final t1 = now - 5000;
        final serverTimeFarAhead =
            now + 10 * 24 * 60 * 60 * 1000; // 10 days in future

        // Create a local rating at device time t1
        await testDb.insert('ratings', {
          'movie_id': 123,
          'is_tv': 0,
          'rating': 3,
          'genre_ids': jsonEncode([28]),
          'title': 'Local Movie',
          'created_at': t1,
          'updated_at': t1,
          'deleted': 0,
        });

        mockApi.pullResponse = {
          'server_time': serverTimeFarAhead,
          'ratings': [],
          'watchlist': [],
          'favorites': [],
          'watched_seasons': [],
          'search_history': [],
        };

        // 2. Act: First Sync
        await syncService.sync();

        // Verify that local rating at t1 was pushed
        expect(mockApi.pushedPayload, isNotNull);
        expect(mockApi.pushedPayload!['ratings'], hasLength(1));

        // Verify that lastSync is the future server time, but lastPush tracks
        // the max pushed updated_at (not wall clock / not server_time).
        final lastSync = await PrefsService.getLastSyncTime();
        final lastPush = await PrefsService.getLastPushTime();
        expect(lastSync, serverTimeFarAhead - 1);
        expect(lastPush, isNot(serverTimeFarAhead));
        expect(lastPush, t1 - 1);

        // 3. Create another local rating at current device time (which is > lastPush, but < serverTimeFarAhead)
        final t2 = DateTime.now().millisecondsSinceEpoch + 1000;
        await testDb.insert('ratings', {
          'movie_id': 124,
          'is_tv': 0,
          'rating': 2,
          'genre_ids': jsonEncode([28]),
          'title': 'Another Local',
          'created_at': t2,
          'updated_at': t2,
          'deleted': 0,
        });

        // 4. Act: Second Sync
        await syncService.sync();

        // The previous watermark row may be replayed, but the new local row
        // must be included even while the device clock trails server time.
        expect(
          mockApi.pushedPayload!['ratings'].map((row) => row['movie_id']),
          contains(124),
        );
      },
    );

    test('empty push does not advance lastPush via wall clock', () async {
      await PrefsService.setLastSyncTime(0);
      await PrefsService.setLastPushTime(42);

      mockApi.pullResponse = {
        'server_time': 9999,
        'ratings': [],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      await syncService.sync();

      expect(await PrefsService.getLastPushTime(), 42);
      expect(mockApi.pushedPayload!['ratings'], isEmpty);
    });

    test(
      'push cursor overlaps one millisecond to replay equal timestamps',
      () async {
        await PrefsService.setLastSyncTime(0);
        await PrefsService.setLastPushTime(0);
        await testDb.insert('ratings', {
          'movie_id': 77,
          'is_tv': 0,
          'rating': 3,
          'genre_ids': '[]',
          'created_at': 5000,
          'updated_at': 5000,
          'deleted': 0,
        });
        mockApi.pullResponse = {
          'server_time': 6000,
          'ratings': [],
          'watchlist': [],
          'favorites': [],
          'watched_seasons': [],
          'search_history': [],
        };

        await syncService.sync();
        expect(await PrefsService.getLastPushTime(), 4999);

        await syncService.sync();
        expect(mockApi.pushedPayload!['ratings'], hasLength(1));
        expect(mockApi.pushedPayload!['ratings'][0]['movie_id'], 77);
      },
    );

    test('should preserve unpushed local data when device expired', () async {
      await testDb.insert('ratings', {
        'movie_id': 10,
        'is_tv': 0,
        'rating': 3,
        'genre_ids': '[]',
        'created_at': 1001,
        'updated_at': 1002,
        'deleted': 0,
      });
      mockApi.resetRequiredOnFirstPush = true;
      mockApi.pullResponse = {
        'server_time': 5000,
        'ratings': [
          {
            'movie_id': 20,
            'is_tv': 0,
            'metadata_locale': 'tr',
            'rating': 4,
            'genre_ids': <int>[],
            'title': 'Cloud Movie',
            'created_at': 4000,
            'updated_at': 4000,
            'deleted': false,
          },
        ],
        'watchlist': [],
        'favorites': [],
        'watched_seasons': [],
        'search_history': [],
      };

      await syncService.sync();

      expect(mockApi.pushCount, 3);
      expect(mockApi.pushedPayloads[1]['ratings'], isEmpty);
      expect(mockApi.pushedPayloads[2]['ratings'], hasLength(2));
      final rows = await testDb.query('ratings');
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['movie_id']), containsAll([10, 20]));
    });
  });
}
