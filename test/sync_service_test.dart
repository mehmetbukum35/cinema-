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
  int? pulledSince;
  Map<String, dynamic> pullResponse = {};
  Map<String, dynamic> pushResponse = {'applied': 0};
  bool shouldThrow = false;
  int pushCount = 0;
  int pullCount = 0;
  Duration? delay;

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushCount++;
    pushedPayload = payload;
    if (delay != null) await Future.delayed(delay!);
    if (shouldThrow) throw Exception('API Error');
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> pull(int since) async {
    pullCount++;
    pulledSince = since;
    if (delay != null) await Future.delayed(delay!);
    if (shouldThrow) throw Exception('API Error');
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
      version: 8,
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
      final ratingsPayload = mockApi.pushedPayload!['ratings'] as List<dynamic>;
      expect(ratingsPayload, hasLength(1));
      expect(ratingsPayload[0]['movie_id'], 123);
      expect(ratingsPayload[0]['rating'], 3);
      expect(ratingsPayload[0]['deleted'], false);

      final watchlistPayload =
          mockApi.pushedPayload!['watchlist'] as List<dynamic>;
      expect(watchlistPayload, hasLength(1));
      expect(watchlistPayload[0]['id'], 456);
      expect(watchlistPayload[0]['deleted'], true);

      // Verify last sync time was updated to 1100
      expect(await PrefsService.getLastSyncTime(), 1100);
    });

    test('should pull remote changes and apply them locally', () async {
      // 1. Arrange: Setup remote changes in Pull Response
      mockApi.pullResponse = {
        'server_time': 2000,
        'ratings': [
          {
            'movie_id': 789,
            'is_tv': 0,
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
            'title': 'Remote Show',
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
        'favorites': [],
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
      expect(jsonDecode(dbRatings[0]['genre_ids'] as String), [12, 14]);

      // Verify watchlist soft-delete was applied locally
      final dbWatchlist = await testDb.query(
        'watchlist',
        where: 'id = ?',
        whereArgs: [999],
      );
      expect(dbWatchlist, hasLength(1));
      expect(dbWatchlist[0]['deleted'], 1);

      // Verify last sync time was updated to server time (2000)
      expect(await PrefsService.getLastSyncTime(), 2000);
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

        // 3. Assert Pushed data
        expect(mockApi.pushedPayload, isNotNull);
        final favsPushed = mockApi.pushedPayload!['favorites'] as List;
        expect(favsPushed, hasLength(1));
        expect(favsPushed[0]['id'], 111);

        final seasonsPushed = mockApi.pushedPayload!['watched_seasons'] as List;
        expect(seasonsPushed, hasLength(1));
        expect(seasonsPushed[0]['tv_id'], 222);

        final searchPushed = mockApi.pushedPayload!['search_history'] as List;
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

    test('should handle device time behind server time using dual watermark', () async {
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

      // Verify that lastSync is the future server time, but lastPush is device time (near 'now')
      final lastSync = await PrefsService.getLastSyncTime();
      final lastPush = await PrefsService.getLastPushTime();
      expect(lastSync, serverTimeFarAhead);
      expect(lastPush, isNot(serverTimeFarAhead));
      expect(lastPush, greaterThan(t1));

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

      // Verify that the second local rating at t2 was pushed because its updated_at (t2) > lastPush (approx now)
      expect(mockApi.pushedPayload!['ratings'], hasLength(1));
      expect(mockApi.pushedPayload!['ratings'][0]['movie_id'], 124);
    });
  });
}
