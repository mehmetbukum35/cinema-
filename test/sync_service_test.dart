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
  Map<String, dynamic> pushResponse = {'applied': true};

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushedPayload = payload;
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> pull(int since) async {
    pulledSince = since;
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
      version: 4,
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
  });
}
