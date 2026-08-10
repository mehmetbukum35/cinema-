import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';
import 'prefs/auth_storage.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';
import 'api_service.dart';
import 'providers.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/top_list_provider.dart';
import '../providers/swipe_provider.dart';
import '../providers/social_provider.dart';
import 'cultural_preference_service.dart';
import '../models/cultural_preferences.dart';
import 'recommendation_telemetry_service.dart';

/// Sunucudan gelen sayısal alanları güvenle int'e çevirir. Paylaşımlı
/// hosting'deki MySQL/PDO, BIGINT kolonları JSON'a STRING olarak yazar
/// (ör. "updated_at":"1783407000000"); doğrudan `as num` cast'i TypeError
/// fırlatır ve sync her seferinde aynı yerde patlar.
int _asInt(Object? v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

double _asDouble(Object? v) =>
    v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

/// JSON bool veya 0/1 int/string → SQLite deleted flag.
int _asDeletedFlag(Object? v) {
  if (v == true || v == 1 || v == '1') return 1;
  if (v is num) return v.toInt() != 0 ? 1 : 0;
  return 0;
}

/// Sunucu ile aynı tolerans (Sync.php clock clamp).
const int _clockSkewMs = 5 * 60 * 1000;

List<dynamic> _decodeJsonList(Object? value) {
  if (value is List) return List<dynamic>.from(value);
  if (value is! String || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    return decoded is List ? List<dynamic>.from(decoded) : const [];
  } on FormatException {
    return const [];
  }
}

/// Bir milisaniyelik örtüşme, watermark ile tam aynı anda yazılan satırların
/// sonraki turda sessizce atlanmasını önler. Push/pull upsert'leri idempotenttir.
int _overlappingCursor(int value) => value > 0 ? value - 1 : 0;

/// Push imlecini cihaz duvar saatine değil, gerçekten gönderilen satırların
/// max(updated_at) değerine bağlar. Boş push'ta 0 → imleç ilerlemeZ (saat
/// ileri kayıp sonra düzeltilince sessiz veri kaybını önler).
int _maxUpdatedAtInPayload(Map<String, dynamic> payload) {
  var maxTs = 0;
  for (final key in const [
    'ratings',
    'watchlist',
    'favorites',
    'watched_seasons',
    'search_history',
  ]) {
    final rows = payload[key];
    if (rows is! List) continue;
    for (final row in rows) {
      if (row is! Map) continue;
      final ts = _asInt(row['updated_at']);
      if (ts > maxTs) maxTs = ts;
    }
  }
  final cultural = payload['cultural_preferences'];
  if (cultural is Map) {
    final ts = _asInt(cultural['updated_at']);
    if (ts > maxTs) maxTs = ts;
  }
  return maxTs;
}

class _SyncSessionChanged implements Exception {
  const _SyncSessionChanged();
}

class SyncService {
  static const int _pushBatchSize = 500;
  final ApiService _apiService;
  final Ref? _ref;
  Future<void>? _syncFuture;

  /// After a local wipe for sync_reset_required, declare local_reset until
  /// one successful sync clears the server-side invalidation.
  bool _declareLocalReset = false;

  SyncService(this._apiService, [this._ref]);

  /// Oturum kapanırken eski ağ işini yeni girişin önünde kilit olarak bırakma.
  ///
  /// Devam eden Future gerçekten iptal edilemez; ancak `_ensureSession` oturum
  /// değişimini fark edip eski işin SQLite transaction'ını commit etmesini
  /// engeller. Referansı bırakmak yeni oturumun kendi sync'ini hemen başlatır.
  void abandonInFlightSync() {
    _syncFuture = null;
    _declareLocalReset = false;
  }

  Future<String?> _currentUserId() async {
    final user = await PrefsAuthStorage.getUserData();
    return user?['id']?.toString();
  }

  Future<void> _ensureSession(String? expectedUserId) async {
    // Unit tests and mock-storage handshakes may intentionally have no user.
    // A real authenticated sync always has persisted user data.
    if (expectedUserId == null) return;
    if (await _currentUserId() != expectedUserId) {
      throw const _SyncSessionChanged();
    }
  }

  Future<int> _pushPayloadInChunks(
    Map<String, dynamic> payload,
    String? sessionUserId,
  ) async {
    const tables = [
      'ratings',
      'watchlist',
      'favorites',
      'watched_seasons',
      'search_history',
    ];
    final maxLength = tables.fold<int>(0, (max, table) {
      final length = (payload[table] as List?)?.length ?? 0;
      return length > max ? length : max;
    });
    final batchCount = maxLength == 0 ? 1 : (maxLength / _pushBatchSize).ceil();
    var applied = 0;

    for (var batch = 0; batch < batchCount; batch++) {
      final start = batch * _pushBatchSize;
      final chunk = <String, dynamic>{
        'metadata_locale': payload['metadata_locale'],
      };
      if (batch == 0 && payload['cultural_preferences'] != null) {
        chunk['cultural_preferences'] = payload['cultural_preferences'];
      }
      if (batch == 0 && payload['recommendation_events'] != null) {
        chunk['recommendation_events'] = payload['recommendation_events'];
      }
      if (payload['local_reset'] == true) {
        chunk['local_reset'] = true;
      }
      for (final table in tables) {
        final items = payload[table] as List? ?? const [];
        if (start < items.length) {
          final candidateEnd = start + _pushBatchSize;
          final end = candidateEnd < items.length ? candidateEnd : items.length;
          chunk[table] = items.sublist(start, end);
        } else {
          chunk[table] = const [];
        }
      }
      await _ensureSession(sessionUserId);
      final result = await _apiService.push(chunk);
      await _ensureSession(sessionUserId);
      applied += _asInt(result['applied']);
      final accepted = (result['accepted_event_ids'] as List?)
          ?.map((id) => id.toString())
          .toSet();
      if (accepted != null) {
        await RecommendationTelemetryService.removeEvents(accepted);
      }
    }
    return applied;
  }

  // Core 2-way delta-sync method
  Future<void> sync() async {
    if (_ref != null) {
      final authState = _ref.read(authProvider);
      if (!authState.isAuthenticated) {
        debugPrint("Skipping sync: user is not authenticated.");
        return;
      }
    }
    if (_syncFuture != null) {
      debugPrint("Sync already in progress, coalescing request.");
      return _syncFuture;
    }
    // Coalesce the recovery wrapper so waiters also get reset recovery /
    // session-change swallow — not the raw _performSync future.
    final currentSync = _syncWithRecovery();
    _syncFuture = currentSync;
    try {
      await currentSync;
    } finally {
      // Çıkış + yeniden giriş arada yeni bir sync başlatmış olabilir. Eski
      // Future tamamlanınca yeni oturumun kilidini yanlışlıkla temizleme.
      if (identical(_syncFuture, currentSync)) {
        _syncFuture = null;
      }
    }
  }

  Future<void> _syncWithRecovery() async {
    try {
      await _performSync();
    } on _SyncSessionChanged {
      debugPrint('Sync cancelled because the authenticated user changed.');
    } on ApiException catch (e) {
      if (e.code != 'sync_reset_required') rethrow;
      debugPrint('Sync device expired; performing a safe full resync.');
      final pendingLocalChanges = await _resetLocalSyncState();
      _declareLocalReset = true;
      try {
        await _performSync();
        await _restorePendingLocalChanges(pendingLocalChanges);
        if (pendingLocalChanges.values.any((rows) => rows.isNotEmpty)) {
          // The full pull advances both cursors. Rewind only the push cursor so
          // the preserved offline edits are uploaded on a second pass.
          await PrefsSyncMeta.setLastPushTime(0);
          await _performSync();
        }
      } catch (e) {
        await _restorePendingLocalChanges(pendingLocalChanges);
        rethrow;
      }
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> _resetLocalSyncState() async {
    final pending = <String, List<Map<String, Object?>>>{};
    final db = await DatabaseHelper().database;
    if (db != null) {
      final lastPush = await PrefsSyncMeta.getLastPushTime();
      await db.transaction((txn) async {
        for (final table in const [
          'ratings',
          'watchlist',
          'favorites',
          'watched_seasons',
          'search_history',
        ]) {
          pending[table] = await txn.query(
            table,
            where: 'updated_at > ?',
            whereArgs: [lastPush],
          );
          await txn.delete(table);
        }
      });
    }
    await PrefsSyncMeta.setLastSyncTime(0);
    await PrefsSyncMeta.setLastPushTime(0);
    PrefsTastePrefs.invalidateGenreWeights();
    await _ref?.read(recommendationEngineProvider).invalidateCache();
    _ref?.invalidate(watchlistProvider);
    _ref?.invalidate(statsProvider);
    // Top 20 (favoriler) de tazelensin — aksi halde giriş/sıfırlama sonrası
    // sunucudan çekilen favoriler bayat provider yüzünden ekrana gelmiyordu.
    _ref?.invalidate(topListProvider);
    _ref?.invalidate(swipeProvider);
    _ref?.invalidate(socialProvider);
    return pending;
  }

  Future<void> _restorePendingLocalChanges(
    Map<String, List<Map<String, Object?>>> pending,
  ) async {
    if (!pending.values.any((rows) => rows.isNotEmpty)) return;
    final db = await DatabaseHelper().database;
    if (db == null) return;

    await db.transaction((txn) async {
      for (final entry in pending.entries) {
        for (final row in entry.value) {
          final (where, args) = switch (entry.key) {
            'ratings' => (
              'movie_id = ? AND is_tv = ?',
              <Object?>[row['movie_id'], row['is_tv']],
            ),
            'watchlist' || 'favorites' => (
              'id = ? AND is_tv = ?',
              <Object?>[row['id'], row['is_tv']],
            ),
            'watched_seasons' => (
              'tv_id = ? AND season_number = ?',
              <Object?>[row['tv_id'], row['season_number']],
            ),
            'search_history' => ('query = ?', <Object?>[row['query']]),
            _ => throw StateError('Unknown sync table: ${entry.key}'),
          };
          final existing = await txn.query(
            entry.key,
            columns: const ['updated_at'],
            where: where,
            whereArgs: args,
            limit: 1,
          );
          if (existing.isNotEmpty &&
              _asInt(existing.first['updated_at']) >
                  _asInt(row['updated_at'])) {
            continue;
          }
          await txn.insert(
            entry.key,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> _performSync() async {
    final sessionUserId = await _currentUserId();
    // İki ayrı imleç tutulur:
    //  - lastPull: sunucu saatiyle (server_time) — pull "since" parametresi.
    //  - lastPush: CİHAZ saatiyle — push adayları yerel updated_at ile seçilir.
    // Tek imleç kullanılırsa cihaz saati sunucudan gerideyken sync sonrası
    // yapılan değişiklikler updated_at < server_time kaldığı için asla push
    // edilmez (sessiz veri kaybı).
    final lastPull = await PrefsSyncMeta.getLastSyncTime();
    final lastPush = await PrefsSyncMeta.getLastPushTime();
    final db = await DatabaseHelper().database;
    if (db == null) {
      // Web / FLUTTER_TEST mock storage: no SQLite, but cloud handshake still runs.
      debugPrint(
        "Starting sync (mock DB). pull since: $lastPull, push since: $lastPush",
      );
      await _ensureSession(sessionUserId);
      final pushResult = await _apiService.push(<String, dynamic>{
        'metadata_locale': _apiService.localeCode(),
        'cultural_preferences': (await CulturalPreferenceService.load())
            .toJson(),
        'recommendation_events':
            await RecommendationTelemetryService.pendingEvents(),
        if (_declareLocalReset) 'local_reset': true,
      });
      await _ensureSession(sessionUserId);
      debugPrint("Push complete. Applied changes: ${pushResult['applied']}");
      final accepted = (pushResult['accepted_event_ids'] as List?)
          ?.map((id) => id.toString())
          .toSet();
      if (accepted != null) {
        await RecommendationTelemetryService.removeEvents(accepted);
      }
      // Mock DB'de gönderilecek satır yok — duvar saatiyle imleç ilerletme.
      await _ensureSession(sessionUserId);
      final pullResult = await _apiService.pull(
        lastPull,
        localReset: _declareLocalReset,
      );
      await _ensureSession(sessionUserId);
      final serverTime = _asInt(pullResult['server_time']);
      await _applyRemoteCulturalPreferences(pullResult);
      await _ensureSession(sessionUserId);
      await PrefsSyncMeta.setLastSyncTime(_overlappingCursor(serverTime));
      PrefsTastePrefs.invalidateGenreWeights();
      await _ref?.read(recommendationEngineProvider).invalidateCache();
      debugPrint(
        "Sync complete (mock DB). pull cursor: $serverTime, push cursor: $lastPush",
      );
      if (_declareLocalReset) {
        _declareLocalReset = false;
      }
      _autoPublishDnaBackground();
      return;
    }

    debugPrint("Starting sync. pull since: $lastPull, push since: $lastPush");

    // İlk sync veya boş imleç: push'tan ÖNCE sunucu saatini alıp sapmış
    // yerel damgaları kırp — yoksa ileri saatli cihaz LWW'yi bir kez bile çalar.
    // lastPull watermark'ı "şimdi" değildir; ona karşı heal etmek sync sonrası
    // meşru düzenlemeleri (5 dk+) eski damgaya çeker ve LWW kaybına yol açar.
    Map<String, dynamic>? earlyPull;
    if (lastPull <= 0) {
      await _ensureSession(sessionUserId);
      earlyPull = await _apiService.pull(0, localReset: _declareLocalReset);
      await _ensureSession(sessionUserId);
      final earlyServer = _asInt(earlyPull['server_time']);
      await _healSkewedLocalTimestamps(db, earlyServer);
    } else {
      await _healSkewedLocalTimestamps(
        db,
        DateTime.now().millisecondsSinceEpoch,
      );
    }

    // 1. Build and PUSH local changes
    final payload = <String, dynamic>{
      'metadata_locale': _apiService.localeCode(),
      if (_declareLocalReset) 'local_reset': true,
    };
    final localCulturalPreferences = await CulturalPreferenceService.load();
    if (localCulturalPreferences.updatedAt > lastPush) {
      payload['cultural_preferences'] = localCulturalPreferences.toJson();
    }
    payload['recommendation_events'] =
        await RecommendationTelemetryService.pendingEvents();

    // Ratings
    final localRatings = await db.query(
      'ratings',
      where: 'updated_at > ?',
      whereArgs: [lastPush],
    );
    payload['ratings'] = localRatings
        .map(
          (r) => {
            'movie_id': r['movie_id'],
            'is_tv': r['is_tv'],
            'metadata_locale': r['metadata_locale'],
            'rating': r['rating'],
            'genre_ids': _decodeJsonList(r['genre_ids']),
            'title': r['title'],
            'poster_path': r['poster_path'],
            'backdrop_path': r['backdrop_path'],
            'overview': r['overview'],
            'vote_average': r['vote_average'],
            'release_date': r['release_date'],
            'popularity': r['popularity'],
            'comment': r['comment'],
            'is_spoiler': r['is_spoiler'],
            'is_private': r['is_private'],
            'original_language': r['original_language'],
            'origin_countries': () {
              final countries = _decodeJsonList(r['origin_countries']);
              return countries.isEmpty ? null : countries;
            }(),
            'created_at': r['created_at'],
            'updated_at': r['updated_at'],
            'deleted': r['deleted'] == 1,
          },
        )
        .toList();

    // Watchlist
    final localWatchlist = await db.query(
      'watchlist',
      where: 'updated_at > ?',
      whereArgs: [lastPush],
    );
    payload['watchlist'] = localWatchlist
        .map(
          (w) => {
            'id': w['id'],
            'is_tv': w['is_tv'],
            'metadata_locale': w['metadata_locale'],
            'title': w['title'],
            'poster_path': w['poster_path'],
            'backdrop_path': w['backdrop_path'],
            'overview': w['overview'],
            'vote_average': w['vote_average'],
            'release_date': w['release_date'],
            'genre_ids': _decodeJsonList(w['genre_ids']),
            'created_at': w['created_at'],
            'updated_at': w['updated_at'],
            'deleted': w['deleted'] == 1,
          },
        )
        .toList();

    // Favorites
    final localFavorites = await db.query(
      'favorites',
      where: 'updated_at > ?',
      whereArgs: [lastPush],
    );
    payload['favorites'] = localFavorites
        .map(
          (f) => {
            'id': f['id'],
            'is_tv': f['is_tv'],
            'metadata_locale': f['metadata_locale'],
            'title': f['title'],
            'poster_path': f['poster_path'],
            'backdrop_path': f['backdrop_path'],
            'overview': f['overview'],
            'vote_average': f['vote_average'],
            'release_date': f['release_date'],
            'genre_ids': _decodeJsonList(f['genre_ids']),
            'created_at': f['created_at'],
            'updated_at': f['updated_at'],
            'deleted': f['deleted'] == 1,
          },
        )
        .toList();

    // Watched Seasons
    final localWatchedSeasons = await db.query(
      'watched_seasons',
      where: 'updated_at > ?',
      whereArgs: [lastPush],
    );
    payload['watched_seasons'] = localWatchedSeasons
        .map(
          (ws) => {
            'tv_id': ws['tv_id'],
            'season_number': ws['season_number'],
            'updated_at': ws['updated_at'],
            'deleted': ws['deleted'] == 1,
          },
        )
        .toList();

    // Search History
    final localSearchHistory = await db.query(
      'search_history',
      where: 'updated_at > ?',
      whereArgs: [lastPush],
    );
    payload['search_history'] = localSearchHistory
        .map(
          (sh) => {
            'query': sh['query'],
            'created_at': sh['created_at'],
            'updated_at': sh['updated_at'],
            'deleted': sh['deleted'] == 1,
          },
        )
        .toList();

    // Push local updates to server
    final applied = await _pushPayloadInChunks(payload, sessionUserId);
    debugPrint("Push complete. Applied changes: $applied");

    // Push imlecini gönderilen satırların max(updated_at)'ine bağla — duvar
    // saati değil. Boş push'ta ilerleme yok (saat geri alınca veri kaybı olmaz).
    // Bir milisaniyelik örtüşme, snapshot alındıktan sonra aynı ms damgasıyla
    // yazılan yerel değişikliklerin sonraki turda kaybolmasını önler.
    final pushedMax = _maxUpdatedAtInPayload(payload);
    final nextPushCursor = pushedMax > lastPush
        ? _overlappingCursor(pushedMax)
        : lastPush;
    if (pushedMax > lastPush) {
      await PrefsSyncMeta.setLastPushTime(nextPushCursor);
    }

    // 2. PULL remote changes (ilk sync'te earlyPull zaten alındı).
    await _ensureSession(sessionUserId);
    final pullResult =
        earlyPull ??
        await _apiService.pull(lastPull, localReset: _declareLocalReset);
    await _ensureSession(sessionUserId);
    final serverTime = _asInt(pullResult['server_time']);
    final culturalChanged = await _applyRemoteCulturalPreferences(pullResult);

    // Sunucudan gelen satır, yereldeki karşılığından ESKİYSE uygulanmaz.
    // Aksi halde sync sürerken yapılan yerel bir değişiklik (ör. yeni puan)
    // sunucunun eski kopyasıyla geri alınırdı (last-write-wins istemcide de
    // uygulanmalı; sunucu tarafı zaten aynı kuralı işletiyor).
    Future<bool> shouldApply(
      DatabaseExecutor txn,
      String table,
      String where,
      List<Object?> args,
      Object? remoteUpdatedAt,
    ) async {
      final rows = await txn.query(
        table,
        columns: ['updated_at'],
        where: where,
        whereArgs: args,
        limit: 1,
      );
      if (rows.isEmpty) return true;
      final local = _asInt(rows.first['updated_at']);
      final remote = _asInt(remoteUpdatedAt);
      // Yerel damga saati sapmışsa (sunucudan >> ileride) remote'u kabul et;
      // aksi halde sapmış cihaz karşı tarafın yazımını sonsuza kadar reddeder.
      if (local > serverTime + _clockSkewMs) return true;
      return remote >= local;
    }

    int appliedCount = 0;

    // Apply remote updates to local SQLite database
    await db.transaction((txn) async {
      // Ratings
      final remoteRatings = pullResult['ratings'] as List<dynamic>? ?? [];
      for (final r in remoteRatings) {
        if (!await shouldApply(txn, 'ratings', 'movie_id = ? AND is_tv = ?', [
          _asInt(r['movie_id']),
          _asInt(r['is_tv']),
        ], r['updated_at'])) {
          continue;
        }
        // Dil/ülke titles join'dan gelebilir; REPLACE ile silinmesin diye yereli koru.
        String? originalLanguage = r['original_language'] as String?;
        Object? originCountries = r['origin_countries'];
        if (originalLanguage == null || originCountries == null) {
          final existing = await txn.query(
            'ratings',
            columns: ['original_language', 'origin_countries'],
            where: 'movie_id = ? AND is_tv = ?',
            whereArgs: [_asInt(r['movie_id']), _asInt(r['is_tv'])],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            originalLanguage ??= existing.first['original_language'] as String?;
            originCountries ??= existing.first['origin_countries'];
          }
        }
        final originCountriesJson = originCountries is List
            ? jsonEncode(List<dynamic>.from(originCountries))
            : (originCountries is String && originCountries.isNotEmpty
                  ? originCountries
                  : null);
        await txn.insert('ratings', {
          'movie_id': _asInt(r['movie_id']),
          'is_tv': _asInt(r['is_tv']),
          'metadata_locale': r['metadata_locale'] ?? _apiService.localeCode(),
          'rating': _asInt(r['rating']),
          'genre_ids': jsonEncode(_decodeJsonList(r['genre_ids'])),
          'title': r['title'],
          'poster_path': r['poster_path'],
          'backdrop_path': r['backdrop_path'],
          'overview': r['overview'],
          'vote_average': _asDouble(r['vote_average']),
          'release_date': r['release_date'],
          'popularity': _asDouble(r['popularity']),
          'comment': r['comment'],
          'is_spoiler': _asInt(r['is_spoiler'] ?? 0),
          'is_private': _asInt(r['is_private'] ?? 0),
          'original_language': originalLanguage,
          'origin_countries': originCountriesJson,
          'created_at': _asInt(r['created_at']),
          'updated_at': _asInt(r['updated_at']),
          'deleted': _asDeletedFlag(r['deleted']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Watchlist
      final remoteWatchlist = pullResult['watchlist'] as List<dynamic>? ?? [];
      for (final w in remoteWatchlist) {
        if (!await shouldApply(txn, 'watchlist', 'id = ? AND is_tv = ?', [
          _asInt(w['id']),
          _asInt(w['is_tv']),
        ], w['updated_at'])) {
          continue;
        }
        await txn.insert('watchlist', {
          'id': _asInt(w['id']),
          'is_tv': _asInt(w['is_tv']),
          'metadata_locale': w['metadata_locale'] ?? _apiService.localeCode(),
          // Compacted legacy tombstones may no longer have catalog metadata.
          // SQLite keeps this legacy column NOT NULL, so retain a harmless
          // placeholder for deleted rows instead of aborting the entire sync.
          'title': w['title'] ?? '',
          'poster_path': w['poster_path'],
          'backdrop_path': w['backdrop_path'],
          'overview': w['overview'],
          'vote_average': _asDouble(w['vote_average']),
          'release_date': w['release_date'],
          'genre_ids': jsonEncode(_decodeJsonList(w['genre_ids'])),
          'created_at': _asInt(w['created_at']),
          'updated_at': _asInt(w['updated_at']),
          'deleted': _asDeletedFlag(w['deleted']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Favorites
      final remoteFavorites = pullResult['favorites'] as List<dynamic>? ?? [];
      for (final f in remoteFavorites) {
        if (!await shouldApply(txn, 'favorites', 'id = ? AND is_tv = ?', [
          _asInt(f['id']),
          _asInt(f['is_tv']),
        ], f['updated_at'])) {
          continue;
        }
        await txn.insert('favorites', {
          'id': _asInt(f['id']),
          'is_tv': _asInt(f['is_tv']),
          'metadata_locale': f['metadata_locale'] ?? _apiService.localeCode(),
          // Favorites has the same legacy NOT NULL constraint as watchlist.
          'title': f['title'] ?? '',
          'poster_path': f['poster_path'],
          'backdrop_path': f['backdrop_path'],
          'overview': f['overview'],
          'vote_average': _asDouble(f['vote_average']),
          'release_date': f['release_date'],
          'genre_ids': jsonEncode(_decodeJsonList(f['genre_ids'])),
          'created_at': _asInt(f['created_at']),
          'updated_at': _asInt(f['updated_at']),
          'deleted': _asDeletedFlag(f['deleted']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Watched Seasons
      final remoteWatchedSeasons =
          pullResult['watched_seasons'] as List<dynamic>? ?? [];
      for (final ws in remoteWatchedSeasons) {
        if (!await shouldApply(
          txn,
          'watched_seasons',
          'tv_id = ? AND season_number = ?',
          [_asInt(ws['tv_id']), _asInt(ws['season_number'])],
          ws['updated_at'],
        )) {
          continue;
        }
        await txn.insert('watched_seasons', {
          'tv_id': _asInt(ws['tv_id']),
          'season_number': _asInt(ws['season_number']),
          'updated_at': _asInt(ws['updated_at']),
          'deleted': _asDeletedFlag(ws['deleted']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Search History
      final remoteSearchHistory =
          pullResult['search_history'] as List<dynamic>? ?? [];
      for (final sh in remoteSearchHistory) {
        if (!await shouldApply(txn, 'search_history', 'query = ?', [
          sh['query'],
        ], sh['updated_at'])) {
          continue;
        }
        await txn.insert('search_history', {
          'query': sh['query'],
          'created_at': _asInt(sh['created_at']),
          'updated_at': _asInt(sh['updated_at']),
          'deleted': _asDeletedFlag(sh['deleted']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }
      // A logout/account switch can happen while SQLite awaits above yield.
      // Throwing here keeps the transaction from committing stale account data.
      await _ensureSession(sessionUserId);
    });

    // Pull sonrası sapmış yerel damgaları sunucu saatine çek (bir sonraki push için).
    await _healSkewedLocalTimestamps(db, serverTime);

    // Birleşik pull sonrası Top 20 tavanını ve sıra indekslerini toparla.
    // Trim/remap updated_at stamps happen AFTER the main push, so push those
    // favorites in the same sync turn (tombstones + remapped ranks).
    await _ensureSession(sessionUserId);
    final normalizeStartMs = DateTime.now().millisecondsSinceEpoch;
    final trimmedFavorites = await DatabaseHelper().normalizeFavoritesCap();
    if (trimmedFavorites > 0) {
      appliedCount += trimmedFavorites;
      debugPrint('Sync trimmed $trimmedFavorites favorites over Top 20 cap.');
    }
    await _ensureSession(sessionUserId);
    await _pushFavoritesTouchedSince(normalizeStartMs, sessionUserId);

    // Pull imleci sunucu saatiyle, push imleci cihaz saatiyle ilerler.
    await _ensureSession(sessionUserId);
    await PrefsSyncMeta.setLastSyncTime(_overlappingCursor(serverTime));
    PrefsTastePrefs.invalidateGenreWeights();

    // Invalidate recommendation engine cache and DNA cache
    await _ref?.read(recommendationEngineProvider).invalidateCache();

    if (appliedCount > 0 || culturalChanged) {
      debugPrint(
        "Sync pulled $appliedCount database changes. Invalidating UI providers.",
      );
      _ref?.invalidate(watchlistProvider);
      _ref?.invalidate(statsProvider);
      // Buluttan gelen favoriler Top 20 raylarına da yansısın (aksi halde
      // provider bayat kalıp giriş sonrası boş görünüyordu).
      _ref?.invalidate(topListProvider);
      _ref?.invalidate(swipeProvider);
      _ref?.invalidate(socialProvider);
      // Buluttan gelen puanlar "Sana Özel" / Tonight seçkisini değiştirir.
      _ref?.read(browseRefreshTriggerProvider.notifier).fire();
    }

    debugPrint(
      "Sync complete. pull cursor: $serverTime, push cursor: $nextPushCursor",
    );
    if (_declareLocalReset) {
      _declareLocalReset = false;
    }
    _autoPublishDnaBackground();
  }

  Future<bool> _applyRemoteCulturalPreferences(
    Map<String, dynamic> pullResult,
  ) async {
    final remote = pullResult['cultural_preferences'];
    if (remote is! Map) return false;
    final normalized = Map<String, dynamic>.from(remote);
    final remoteValue = CulturalPreferences.fromJson(normalized);
    final localValue = await CulturalPreferenceService.load();
    if (remoteValue.updatedAt < localValue.updatedAt) return false;
    await CulturalPreferenceService.saveSnapshot(remoteValue);
    return jsonEncode(remoteValue.toJson()) != jsonEncode(localValue.toJson());
  }

  void _autoPublishDnaBackground() {
    final ref = _ref;
    if (ref == null) return;

    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;

    Future.microtask(() async {
      try {
        final userId = auth.user?['id']?.toString();
        await _ensureSession(userId);
        final generated = await ref
            .read(tasteDnaServiceProvider)
            .generate(userId: userId);
        final dna = generated.dna;
        final currentHash = generated.hash;
        final lastPublishedHash =
            await PrefsTastePrefs.getLastPublishedDnaHash();

        if (currentHash != lastPublishedHash) {
          await _ensureSession(userId);
          await _apiService.publishTasteDna(dna.toJson());
          await _ensureSession(userId);
          await PrefsTastePrefs.setLastPublishedDnaHash(currentHash);
          debugPrint("Sync auto-publish DNA succeeded!");
        } else {
          debugPrint("Sync auto-publish DNA skipped (already up to date).");
        }
      } catch (e) {
        debugPrint("Sync auto-publish DNA failed: $e");
      }
    });
  }

  /// İleri saatli cihaz damgalarını sunucu çapasının +skew üstüne kırpar.
  /// Böylece sapmış updated_at LWW'yi kalıcı kilitlemez.
  Future<void> _healSkewedLocalTimestamps(
    Database db,
    int serverAnchorMs,
  ) async {
    if (serverAnchorMs <= 0) return;
    final cap = serverAnchorMs + _clockSkewMs;
    for (final table in const [
      'ratings',
      'watchlist',
      'favorites',
      'watched_seasons',
      'search_history',
    ]) {
      await db.rawUpdate(
        'UPDATE $table SET updated_at = ? WHERE updated_at > ?',
        [serverAnchorMs, cap],
      );
    }
  }

  /// Push favorites rows touched at/after [sinceMs] (cap trim tombstones +
  /// remapped ranks) so they leave in the same sync turn as normalize.
  Future<void> _pushFavoritesTouchedSince(
    int sinceMs,
    String? sessionUserId,
  ) async {
    final db = await DatabaseHelper().database;
    if (db == null) return;

    final rows = await db.query(
      'favorites',
      where: 'updated_at >= ?',
      whereArgs: [sinceMs],
    );
    if (rows.isEmpty) return;

    final payload = <String, dynamic>{
      'metadata_locale': _apiService.localeCode(),
      'favorites': rows
          .map(
            (f) => {
              'id': f['id'],
              'is_tv': f['is_tv'],
              'metadata_locale': f['metadata_locale'],
              'title': f['title'],
              'poster_path': f['poster_path'],
              'backdrop_path': f['backdrop_path'],
              'overview': f['overview'],
              'vote_average': f['vote_average'],
              'release_date': f['release_date'],
              'genre_ids': _decodeJsonList(f['genre_ids']),
              'created_at': f['created_at'],
              'updated_at': f['updated_at'],
              'deleted': f['deleted'] == 1,
            },
          )
          .toList(),
    };

    final applied = await _pushPayloadInChunks(payload, sessionUserId);
    final pushedMax = _maxUpdatedAtInPayload(payload);
    if (pushedMax > 0) {
      final lastPush = await PrefsSyncMeta.getLastPushTime();
      if (pushedMax > lastPush) {
        await PrefsSyncMeta.setLastPushTime(_overlappingCursor(pushedMax));
      }
    }
    debugPrint(
      'Sync pushed ${rows.length} favorites after cap normalize '
      '(applied=$applied).',
    );
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return SyncService(apiService, ref);
});

enum SyncStatus { idle, syncing, success, error }

class SyncNotifier extends Notifier<SyncStatus> {
  /// Testler sahte servisi buradan enjekte eder; uretimde syncServiceProvider.
  final SyncService? _syncServiceOverride;

  /// false → oturum durumu sorgulanmaz. Testler bunu kapatarak notifier'i auth
  /// kablolamasi olmadan surer (migrasyon oncesi `ref` bos birakiliyordu).
  final bool enforceAuth;

  // `late final` DEGIL: Riverpod 3'te invalidate/rebuild ayni notifier ornegi
  // uzerinde build()'i yeniden kosar, ikinci atama LateInitializationError verir.
  late SyncService _syncService;

  SyncNotifier({SyncService? syncService, this.enforceAuth = true})
    : _syncServiceOverride = syncService;

  @override
  SyncStatus build() {
    _syncService = _syncServiceOverride ?? ref.watch(syncServiceProvider);
    return SyncStatus.idle;
  }

  Future<void> performSync() async {
    if (enforceAuth && !ref.read(authProvider).isAuthenticated) {
      state = SyncStatus.idle;
      return;
    }
    state = SyncStatus.syncing;
    try {
      // Eşzamanlı çağrıları birleştirme sorumluluğu SyncService'tedir. İkinci
      // bir kilit aynı davranışı iki katmanda tutup durum yönetimini karmaşıklaştırıyordu.
      await _syncService.sync();
      state = SyncStatus.success;
    } catch (e) {
      if (enforceAuth && !ref.read(authProvider).isAuthenticated) {
        state = SyncStatus.idle;
        return;
      }
      debugPrint("SyncNotifier: Sync failed: $e");
      state = SyncStatus.error;
      rethrow;
    }
  }

  void resetStatus() {
    state = SyncStatus.idle;
  }

  void resetForSessionChange() {
    _syncService.abandonInFlightSync();
    state = SyncStatus.idle;
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncStatus>(
  SyncNotifier.new,
);
