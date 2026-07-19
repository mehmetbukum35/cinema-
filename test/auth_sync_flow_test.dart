// Auth + Sync uçtan uca akış testi.
//
// Birim testlerden farkı: burada hiçbir servis mock'lanmaz. Gerçek ApiService
// (HTTP katmanı dahil), gerçek SyncService ve gerçek SQLite (ffi) birlikte,
// backend'in HTTP sözleşmesini birebir taklit eden DURUM TUTAN sahte bir
// sunucuya (FakeBackend) karşı çalışır. Böylece parçalar tek tek yeşilken
// aralarındaki zincirin kopması (imleç kayması, çakışma çözümü, token
// yenileme yarışı, oturum düşmesi) regresyona karşı kilitlenir.
//
// Senaryolar:
//  1. login → yerel puanlama → sync push → sunucuda görünür
//  2. ikinci cihaz sıfır imleçle pull → veri oraya iner
//  3. last-write-wins iki yönde (sunucu yenisi kazanır / yerel yenisi kazanır)
//  4. süresi dolan access token sync ortasında sessizce yenilenir (rotasyon)
//  5. refresh reddedilirse oturum düşer ama YEREL VERİ KORUNUR
//  6. logout → yerel veri durur; yeniden login + sıfır imleç → idempotent re-push
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/sync_service.dart';

import 'mocks/secure_storage_mock.dart';

/// Backend'in (backend/api + Sync.php + Auth.php) HTTP sözleşmesini taklit
/// eden, istekler arasında durum tutan sahte sunucu. Gerçek sunucuyla aynı
/// kuralları işletir: bearer doğrulama, refresh rotasyonu, last-write-wins.
class FakeBackend {
  static const email = 'user@test.com';
  static const password = 'secret123';
  static const uid = 1;

  static const _tables = [
    'ratings',
    'watchlist',
    'favorites',
    'watched_seasons',
    'search_history',
  ];

  /// table -> rowKey -> row (tek kullanıcı yeterli; sunucu tarafı depo).
  final Map<String, Map<String, Map<String, dynamic>>> store = {
    for (final t in _tables) t: {},
  };

  final Set<String> validAccess = {};
  final Set<String> validRefresh = {};
  int _tokenSeq = 0;

  int loginCalls = 0;
  int refreshCalls = 0;
  int pushCalls = 0;
  int pullCalls = 0;

  /// true → refresh ucu her token'ı reddeder (oturum düşürme senaryosu).
  bool rejectRefresh = false;

  Map<String, String> issueTokens() {
    _tokenSeq++;
    final access = 'acc_$_tokenSeq';
    final refresh = 'ref_$_tokenSeq';
    validAccess.add(access);
    validRefresh.add(refresh);
    return {'access_token': access, 'refresh_token': refresh};
  }

  /// Access token'ların süresinin dolmasını simüle eder (refresh'ler kalır).
  void expireAccessTokens() => validAccess.clear();

  String _rowKey(String table, Map<String, dynamic> item) => switch (table) {
    'ratings' => '${item['movie_id']}|${item['is_tv']}',
    'watchlist' || 'favorites' => '${item['id']}|${item['is_tv']}',
    'watched_seasons' => '${item['tv_id']}|${item['season_number']}',
    _ => '${item['query']}',
  };

  /// Sunucudaki Sync::upsert ile aynı kural: gelen updated_at mevcut satırdan
  /// eskiyse yok sayılır (last-write-wins).
  int _applyPush(Map<String, dynamic> payload) {
    var applied = 0;
    for (final table in _tables) {
      final items = payload[table];
      if (items is! List) continue;
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        final key = _rowKey(table, item);
        final existing = store[table]![key];
        final incomingAt = (item['updated_at'] as num?)?.toInt() ?? 0;
        final existingAt = (existing?['updated_at'] as num?)?.toInt() ?? -1;
        if (existing != null && incomingAt < existingAt) continue;
        store[table]![key] = item;
        applied++;
      }
    }
    return applied;
  }

  List<Map<String, dynamic>> _pullRows(String table, int since) => [
    for (final row in store[table]!.values)
      if (((row['updated_at'] as num?)?.toInt() ?? 0) > since) row,
  ];

  http.Response _json(int status, Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  bool _authorized(http.Request req) {
    final header = req.headers['Authorization'] ?? '';
    return header.startsWith('Bearer ') &&
        validAccess.contains(header.substring(7));
  }

  Future<http.Response> handle(http.Request req) async {
    // baseUrl https://.../api → yol '/api/...'; ön eki at.
    var path = req.url.path;
    if (path.startsWith('/api')) path = path.substring(4);

    if (req.method == 'POST' && path == '/auth/login') {
      loginCalls++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['email'] != email || body['password'] != password) {
        return _json(401, {
          'error': 'E-posta veya parola hatalı.',
          'code': 'invalid_credentials',
        });
      }
      return _json(200, {
        'user': {
          'id': uid,
          'email': email,
          'display_name': 'Test User',
          'username': 'testuser',
          'google_sub': null,
        },
        'tokens': issueTokens(),
      });
    }

    if (req.method == 'POST' && path == '/auth/refresh') {
      refreshCalls++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final rt = body['refresh_token'] as String? ?? '';
      if (rejectRefresh || !validRefresh.contains(rt)) {
        return _json(401, {
          'error': 'Geçersiz veya süresi dolmuş yenileme anahtarı.',
        });
      }
      validRefresh.remove(rt); // rotasyon: eski refresh tek kullanımlık
      return _json(200, {'tokens': issueTokens()});
    }

    if (req.method == 'POST' && path == '/auth/logout') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      validRefresh.remove(body['refresh_token']);
      return _json(200, {'ok': true});
    }

    if (path == '/sync') {
      if (!_authorized(req)) {
        return _json(401, {'error': 'Geçersiz veya süresi dolmuş oturum.'});
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (req.method == 'POST') {
        pushCalls++;
        final payload = jsonDecode(req.body) as Map<String, dynamic>;
        final applied = _applyPush(payload);
        return _json(200, {'server_time': now, 'applied': applied});
      }
      pullCalls++;
      final since = int.tryParse(req.url.queryParameters['since'] ?? '') ?? 0;
      return _json(200, {
        'server_time': now,
        for (final t in _tables) t: _pullRows(t, since),
      });
    }

    return _json(404, {'error': 'Bilinmeyen uç: ${req.method} $path'});
  }
}

Movie makeMovie(int id, {bool isTV = false}) => Movie(
  id: id,
  title: 'Movie $id',
  posterPath: '/p$id.jpg',
  overview: 'Overview $id',
  voteAverage: 7.5,
  releaseDate: '2024-01-0${(id % 9) + 1}',
  isTV: isTV,
  genreIds: const [28, 12],
  popularity: 50,
  voteCount: 500,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setupSecureStorageMock();

  late FakeBackend backend;
  late ApiService api;
  late SyncService syncService;
  late Database deviceDb;
  bool sessionExpiredFired = false;

  Future<Database> openDeviceDb() => openDatabase(
    inMemoryDatabasePath,
    version: 9,
    onCreate: DatabaseHelper().onCreate,
    onUpgrade: DatabaseHelper().onUpgrade,
  );

  /// completeLogin'in servis-katmanı karşılığı: token + kullanıcı kaydet,
  /// imleçleri sıfırla.
  Future<void> login() async {
    final data = await api.login(
      email: FakeBackend.email,
      password: FakeBackend.password,
    );
    final tokens = data['tokens'] as Map<String, dynamic>;
    await PrefsService.saveTokens(
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
    );
    await PrefsService.saveUserData(data['user'] as Map<String, dynamic>);
    await PrefsService.setLastSyncTime(0);
    await PrefsService.setLastPushTime(0);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsService.activeLanguageCode = 'tr';
    sessionExpiredFired = false;

    backend = FakeBackend();
    api = ApiService(
      client: MockClient(backend.handle),
      onSessionExpired: () => sessionExpiredFired = true,
    );
    syncService = SyncService(api);

    deviceDb = await openDeviceDb();
    DatabaseHelper.databaseInstance = deviceDb;
    await PrefsService.clearAuthData(); // statik token cache'ini de sıfırlar
  });

  tearDown(() async {
    await deviceDb.close();
    DatabaseHelper.databaseInstance = null;
  });

  group('Auth + Sync uçtan uca akış (sahte backend, gerçek SQLite)', () {
    test('login → yerel puanlama → sync: veri sunucuya ulaşır', () async {
      await login();

      await PrefsService.saveRating(movie: makeMovie(101), rating: 3);
      await PrefsService.addToWatchlist(makeMovie(202, isTV: true));

      await syncService.sync();

      final serverRating = backend.store['ratings']!['101|0'];
      expect(serverRating, isNotNull);
      expect(serverRating!['rating'], 3);
      expect(serverRating['title'], 'Movie 101');
      expect(serverRating['deleted'], false);
      expect(backend.store['watchlist']!['202|1'], isNotNull);

      // İmleçler ilerledi: bir sonraki sync boş delta göndermeli.
      expect(await PrefsService.getLastSyncTime(), greaterThan(0));
      await syncService.sync();
      expect(backend.pushCalls, 2);
      final secondPush = backend.store['ratings']!.length;
      expect(secondPush, 1); // kopya üretmedi
    });

    test('ikinci cihaz sıfır imleçle pull: veri oraya iner', () async {
      await login();
      await PrefsService.saveRating(movie: makeMovie(101), rating: 2);
      await syncService.sync();

      // ── Cihaz B: taze DB + sıfır imleçler (aynı hesap) ──
      final deviceB = await openDeviceDb();
      DatabaseHelper.databaseInstance = deviceB;
      await PrefsService.setLastSyncTime(0);
      await PrefsService.setLastPushTime(0);

      await syncService.sync();

      final rows = await deviceB.query('ratings');
      expect(rows, hasLength(1));
      expect(rows.first['movie_id'], 101);
      expect(rows.first['rating'], 2);
      expect(rows.first['deleted'], 0);

      await deviceB.close();
      DatabaseHelper.databaseInstance = deviceDb;
    });

    test('last-write-wins: yeni olan kazanır (iki yönde)', () async {
      await login();
      final now = DateTime.now().millisecondsSinceEpoch;

      Map<String, dynamic> serverRating(int movieId, int rating, int at) => {
        'movie_id': movieId,
        'is_tv': 0,
        'rating': rating,
        'genre_ids': [28],
        'title': 'Server $movieId',
        'poster_path': null,
        'backdrop_path': null,
        'overview': null,
        'vote_average': 6.0,
        'release_date': null,
        'popularity': 1.0,
        'comment': null,
        'is_spoiler': 0,
        'is_private': 0,
        'created_at': at,
        'updated_at': at,
        'deleted': false,
      };

      Future<void> insertLocal(int movieId, int rating, int at) =>
          deviceDb.insert('ratings', {
            'movie_id': movieId,
            'is_tv': 0,
            'rating': rating,
            'genre_ids': '[28]',
            'title': 'Local $movieId',
            'created_at': at,
            'updated_at': at,
            'deleted': 0,
          });

      // Yapım 1: sunucu kopyası daha YENİ → yerel ezilmeli.
      await insertLocal(1, 0, now - 5000);
      backend.store['ratings']!['1|0'] = serverRating(1, 3, now + 5000);

      // Yapım 2: yerel kopya daha YENİ → yerel korunmalı, sunucu güncellenmeli.
      await insertLocal(2, 3, now + 5000);
      backend.store['ratings']!['2|0'] = serverRating(2, 0, now - 5000);

      await syncService.sync();

      final r1 = (await deviceDb.query('ratings', where: 'movie_id = 1')).first;
      expect(r1['rating'], 3, reason: 'sunucunun yeni kopyası kazanmalı');
      expect(r1['title'], 'Server 1');

      final r2 = (await deviceDb.query('ratings', where: 'movie_id = 2')).first;
      expect(r2['rating'], 3, reason: 'yerel yeni kopya korunmalı');
      expect(r2['title'], 'Local 2');
      expect(
        backend.store['ratings']!['2|0']!['title'],
        'Local 2',
        reason: 'sunucu, yerel yeni kopyayla güncellenmeli',
      );
    });

    test(
      'süresi dolan access token sync ortasında sessizce yenilenir',
      () async {
        await login();
        await PrefsService.saveRating(movie: makeMovie(101), rating: 3);

        backend.expireAccessTokens(); // access öldü, refresh hâlâ geçerli

        await syncService.sync(); // 401 → refresh → retry, hata fırlatmamalı

        expect(backend.refreshCalls, 1);
        expect(backend.store['ratings']!['101|0'], isNotNull);
        expect(sessionExpiredFired, isFalse);

        // Rotasyon: yeni refresh token kaydedildi ve bir SONRAKİ yenileme de
        // çalışıyor (eski token'la değil).
        backend.expireAccessTokens();
        await syncService.sync();
        expect(backend.refreshCalls, 2);
        expect(sessionExpiredFired, isFalse);
      },
    );

    test('refresh reddedilirse oturum düşer ama yerel veri korunur', () async {
      await login();
      await PrefsService.saveRating(movie: makeMovie(101), rating: 3);

      backend.expireAccessTokens();
      backend.rejectRefresh = true;

      await expectLater(
        syncService.sync(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      expect(sessionExpiredFired, isTrue);
      expect(await PrefsService.getAccessToken(), isNull);
      expect(await PrefsService.getRefreshToken(), isNull);

      // Çekirdek vaat: oturum düşse bile cihazdaki veri durur.
      final rows = await deviceDb.query('ratings');
      expect(rows, hasLength(1));
      expect(rows.first['rating'], 3);
    });

    test(
      'logout yerel veriyi korur; yeniden login idempotent re-push yapar',
      () async {
        await login();
        await PrefsService.saveRating(movie: makeMovie(101), rating: 3);
        await syncService.sync();

        await api.logout(); // sunucuda refresh iptal + yerel auth temizliği
        expect(await PrefsService.getAccessToken(), isNull);
        expect(await deviceDb.query('ratings'), hasLength(1));

        // Yeniden giriş: imleçler sıfırlanır → tüm yerel veri yeniden push
        // edilir; upsert idempotent olduğundan sunucuda kopya oluşmaz.
        await login();
        await syncService.sync();

        expect(backend.store['ratings']!.length, 1);
        expect(backend.store['ratings']!['101|0']!['rating'], 3);
        expect(await deviceDb.query('ratings'), hasLength(1));
      },
    );
  });
}
