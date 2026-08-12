import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs/sync_meta.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

/// Pull sırasında bir geri çağrı çalıştıran sahte API: sync sürerken yapılan
/// yerel bir yazımı taklit etmenin tek yolu, çünkü o pencere ana push ile
/// normalize arasında.
class _PullHookApi implements ApiService {
  _PullHookApi(this.onPull);

  final Future<void> Function() onPull;
  final List<Map<String, dynamic>> pushes = [];

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushes.add(payload);
    return {'applied': 0, 'server_time': DateTime.now().millisecondsSinceEpoch};
  }

  @override
  Future<Map<String, dynamic>> pull(
    int since, {
    bool localReset = false,
  }) async {
    await onPull();
    return {
      'server_time': DateTime.now().millisecondsSinceEpoch,
      'ratings': const [],
      'watchlist': const [],
      'favorites': const [],
      'watched_seasons': const [],
      'search_history': const [],
    };
  }

  @override
  String Function() localeCode = () => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sync_last_time': 1000});
    PrefsService.resetInMemoryCaches();
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 9,
      onCreate: DatabaseHelper().onCreate,
      onUpgrade: DatabaseHelper().onUpgrade,
    );
    DatabaseHelper.databaseInstance = db;
    await PrefsSyncMeta.setLastPushTime(1000);
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.databaseInstance = null;
  });

  // Favori normalize push'u YALNIZ favori satırları taşır; global push imleci
  // ise tüm tablolar için "buraya kadar gönderildi" anlamına gelir. İmleci o
  // push'un duvar-saati damgasına atlatmak, ana push ile normalize arasında
  // (yani bir ağ turu boyunca) yapılan her yerel yazımı sessizce atlar.
  test('favori normalize push"u araya giren yerel yazımı atlamaz', () async {
    // Sıra indeksi bozuk favori: normalize onu remap edip damgalayacak, yani
    // _pushFavoritesTouchedSince gerçekten bir push yapacak.
    await db.insert('favorites', {
      'id': 111,
      'is_tv': 0,
      'title': 'Fav',
      'poster_path': '/p.jpg',
      'backdrop_path': '/b.jpg',
      'overview': '',
      'vote_average': 8.0,
      'release_date': '2026-01-01',
      'genre_ids': jsonEncode([28]),
      'created_at': 5,
      'updated_at': 1010,
      'deleted': 0,
    });

    var injected = false;
    final api = _PullHookApi(() async {
      if (injected) return;
      injected = true;
      // Ana push'tan SONRA, normalize'dan ÖNCE gelen yerel puan.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('ratings', {
        'movie_id': 777,
        'is_tv': 0,
        'rating': 3,
        'genre_ids': jsonEncode([28]),
        'title': 'Sync sırasında verilen puan',
        'poster_path': '/p.jpg',
        'backdrop_path': '/b.jpg',
        'overview': '',
        'vote_average': 8.0,
        'release_date': '2026-01-01',
        'popularity': 10.0,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      });
      // Gerçek pull bir ağ turu sürer; normalize damgası yazımdan sonraya düşsün.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final sync = SyncService(api);
    await sync.sync();
    await sync.sync();

    final pushedRatingIds = [
      for (final push in api.pushes)
        for (final row in (push['ratings'] as List? ?? const []))
          (row as Map)['movie_id'],
    ];
    expect(
      pushedRatingIds,
      contains(777),
      reason: 'Araya giren puan hiçbir push"a girmedi — imleç üstünden atladı',
    );
  });
}
