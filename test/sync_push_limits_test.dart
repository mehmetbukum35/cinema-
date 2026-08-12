import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/recommendation_telemetry_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

/// Sunucunun push sınırlarını birebir uygulayan sahte API
/// (bkz. `backend/src/Sync.php`: MAX_ITEMS_PER_TABLE, MAX_TOTAL_ITEMS_PER_PUSH).
///
/// İstemci parçalaması bu sınırları AŞARSA her deneme aynı fazla-büyük isteği
/// üretir, 413 döner ve sync kalıcı olarak durur — telemetri de kullanıcı
/// verisi de bir daha gitmez. Bu yüzden sınır testte taklit ediliyor.
class ServerLimitApi implements ApiService {
  static const maxPerTable = 500;
  static const maxTotal = 1000;
  static const tables = [
    'ratings',
    'watchlist',
    'favorites',
    'watched_seasons',
    'search_history',
  ];

  final List<int> chunkTotals = [];
  final Map<String, int> deliveredByTable = {for (final t in tables) t: 0};
  int deliveredEvents = 0;

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    var total = 0;
    for (final table in tables) {
      final rows = (payload[table] as List?) ?? const [];
      if (rows.length > maxPerTable) {
        throw ApiException(
          statusCode: 413,
          message: 'Çok fazla kayıt: $table (${rows.length}).',
        );
      }
      total += rows.length;
      deliveredByTable[table] = deliveredByTable[table]! + rows.length;
    }
    final events = (payload['recommendation_events'] as List?) ?? const [];
    if (events.length > maxPerTable) {
      throw ApiException(
        statusCode: 413,
        message: 'Çok fazla recommendation_events kaydı (${events.length}).',
      );
    }
    total += events.length;
    deliveredEvents += events.length;

    chunkTotals.add(total);
    if (total > maxTotal) {
      throw ApiException(
        statusCode: 413,
        message: 'Tek push isteğinde en fazla $maxTotal kayıt ($total).',
      );
    }
    return {
      'applied': total,
      'server_time': 2000,
      'accepted_event_ids': [for (final e in events) e['event_id']],
    };
  }

  @override
  Future<Map<String, dynamic>> pull(
    int since, {
    bool localReset = false,
  }) async => {
    'server_time': 2000,
    for (final table in tables) table: const [],
  };

  @override
  String Function() localeCode = () => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late ServerLimitApi api;
  late SyncService syncService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sync_last_time': 1000});
    PrefsService.resetInMemoryCaches();
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 9,
      onCreate: DatabaseHelper().onCreate,
      onUpgrade: DatabaseHelper().onUpgrade,
    );
    DatabaseHelper.databaseInstance = testDb;
    api = ServerLimitApi();
    syncService = SyncService(api);
  });

  tearDown(() async {
    await testDb.close();
    DatabaseHelper.databaseInstance = null;
  });

  Future<void> seedRatings(int count) async {
    for (var i = 1; i <= count; i++) {
      await testDb.insert('ratings', {
        'movie_id': i,
        'is_tv': 0,
        'rating': 3,
        'genre_ids': jsonEncode([28]),
        'title': 'M$i',
        'poster_path': '/p.jpg',
        'backdrop_path': '/b.jpg',
        'overview': '',
        'vote_average': 8.0,
        'release_date': '2026-01-01',
        'popularity': 10.0,
        'created_at': 1005,
        'updated_at': 1010,
        'deleted': 0,
      });
    }
  }

  Future<void> seedSimple(String table, int count) async {
    for (var i = 1; i <= count; i++) {
      await testDb.insert(table, {
        'id': i,
        'is_tv': 0,
        'title': '$table$i',
        'poster_path': '/p.jpg',
        'backdrop_path': '/b.jpg',
        'overview': '',
        'vote_average': 7.0,
        'release_date': '2026-01-01',
        'genre_ids': jsonEncode([18]),
        'created_at': 1006,
        'updated_at': 1015,
        'deleted': 0,
      });
    }
  }

  test('birden çok dolu tablo, sunucu toplam sınırını aşmadan gönderilir', () async {
    await seedRatings(600);
    await seedSimple('watchlist', 550);
    await seedSimple('favorites', 120);

    await syncService.sync();

    expect(api.chunkTotals, isNotEmpty);
    expect(
      api.chunkTotals.every((t) => t <= ServerLimitApi.maxTotal),
      isTrue,
      reason: 'Sunucu sınırını aşan chunk: ${api.chunkTotals}',
    );
    // Hiçbir satır düşmemeli: parçalama böler, eksiltmez. Favoriler sıra
    // normalizasyonu yüzünden ayrı bir push'ta tekrar gidebilir (bkz.
    // _pushFavoritesTouchedSince), o yüzden alt sınır.
    expect(api.deliveredByTable['ratings'], 600);
    expect(api.deliveredByTable['watchlist'], 550);
    expect(api.deliveredByTable['favorites'], greaterThanOrEqualTo(120));
  });

  test('telemetri kuyruğu dolu iken push tıkanmaz ve kuyruk boşalır', () async {
    await seedRatings(500);
    await seedSimple('watchlist', 1);
    await RecommendationTelemetryService.recordShown([
      for (var i = 1; i <= 500; i++)
        Movie(id: i, title: 'M$i', overview: '', voteAverage: 7),
    ], surface: 'swipe');

    await syncService.sync();

    expect(
      api.chunkTotals.every((t) => t <= ServerLimitApi.maxTotal),
      isTrue,
      reason: 'Sunucu sınırını aşan chunk: ${api.chunkTotals}',
    );
    expect(api.deliveredEvents, 500);
    expect(await RecommendationTelemetryService.pendingEvents(), isEmpty);
  });

  test('gönderilecek satır yokken de tek bir push yapılır', () async {
    await syncService.sync();

    expect(api.chunkTotals, hasLength(1));
    expect(api.chunkTotals.single, 0);
  });
}
