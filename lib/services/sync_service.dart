import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'api_service.dart';
import 'providers.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/top_list_provider.dart';
import '../providers/swipe_provider.dart';
import '../providers/social_provider.dart';

/// Sunucudan gelen sayısal alanları güvenle int'e çevirir. Paylaşımlı
/// hosting'deki MySQL/PDO, BIGINT kolonları JSON'a STRING olarak yazar
/// (ör. "updated_at":"1783407000000"); doğrudan `as num` cast'i TypeError
/// fırlatır ve sync her seferinde aynı yerde patlar.
int _asInt(Object? v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

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
  return maxTs;
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

  Future<int> _pushPayloadInChunks(Map<String, dynamic> payload) async {
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
      final result = await _apiService.push(chunk);
      applied += _asInt(result['applied']);
    }
    return applied;
  }

  // Core 2-way delta-sync method
  Future<void> sync() async {
    if (_syncFuture != null) {
      debugPrint("Sync already in progress, coalescing request.");
      return _syncFuture;
    }
    _syncFuture = _performSync();
    try {
      await _syncFuture;
    } on ApiException catch (e) {
      if (e.code != 'sync_reset_required') rethrow;
      debugPrint('Sync device expired; performing a safe full resync.');
      final pendingLocalChanges = await _resetLocalSyncState();
      _declareLocalReset = true;
      try {
        _syncFuture = _performSync();
        await _syncFuture;
        await _restorePendingLocalChanges(pendingLocalChanges);
        if (pendingLocalChanges.values.any((rows) => rows.isNotEmpty)) {
          // The full pull advances both cursors. Rewind only the push cursor so
          // the preserved offline edits are uploaded on a second pass.
          await PrefsService.setLastPushTime(0);
          _syncFuture = _performSync();
          await _syncFuture;
        }
      } catch (e) {
        await _restorePendingLocalChanges(pendingLocalChanges);
        rethrow;
      }
    } finally {
      _syncFuture = null;
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> _resetLocalSyncState() async {
    final pending = <String, List<Map<String, Object?>>>{};
    final db = await DatabaseHelper().database;
    if (db != null) {
      final lastPush = await PrefsService.getLastPushTime();
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
    await PrefsService.setLastSyncTime(0);
    await PrefsService.setLastPushTime(0);
    PrefsService.invalidateGenreWeights();
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
    // İki ayrı imleç tutulur:
    //  - lastPull: sunucu saatiyle (server_time) — pull "since" parametresi.
    //  - lastPush: CİHAZ saatiyle — push adayları yerel updated_at ile seçilir.
    // Tek imleç kullanılırsa cihaz saati sunucudan gerideyken sync sonrası
    // yapılan değişiklikler updated_at < server_time kaldığı için asla push
    // edilmez (sessiz veri kaybı).
    final lastPull = await PrefsService.getLastSyncTime();
    final lastPush = await PrefsService.getLastPushTime();
    final db = await DatabaseHelper().database;
    if (db == null) {
      // Web / FLUTTER_TEST mock storage: no SQLite, but cloud handshake still runs.
      debugPrint(
        "Starting sync (mock DB). pull since: $lastPull, push since: $lastPush",
      );
      final pushResult = await _apiService.push(<String, dynamic>{
        'metadata_locale': PrefsService.activeLanguageCode,
        if (_declareLocalReset) 'local_reset': true,
      });
      debugPrint("Push complete. Applied changes: ${pushResult['applied']}");
      // Mock DB'de gönderilecek satır yok — duvar saatiyle imleç ilerletme.
      final pullResult = await _apiService.pull(
        lastPull,
        localReset: _declareLocalReset,
      );
      final serverTime = _asInt(pullResult['server_time']);
      await PrefsService.setLastSyncTime(_overlappingCursor(serverTime));
      PrefsService.invalidateGenreWeights();
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

    // 1. Build and PUSH local changes
    final payload = <String, dynamic>{
      'metadata_locale': PrefsService.activeLanguageCode,
      if (_declareLocalReset) 'local_reset': true,
    };

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
    final applied = await _pushPayloadInChunks(payload);
    debugPrint("Push complete. Applied changes: $applied");

    // Push imlecini gönderilen satırların max(updated_at)'ine bağla — duvar
    // saati değil. Boş push'ta ilerleme yok (saat geri alınca veri kaybı olmaz).
    // Inclusive: `updated_at > lastPush` bir sonraki turda aynı satırı
    // yeniden seçmez; sync sırasında yazılan daha yeni satırlar yakalanır.
    final pushedMax = _maxUpdatedAtInPayload(payload);
    if (pushedMax > lastPush) {
      await PrefsService.setLastPushTime(pushedMax);
    }

    // 2. PULL remote changes
    final pullResult = await _apiService.pull(
      lastPull,
      localReset: _declareLocalReset,
    );
    final serverTime = _asInt(pullResult['server_time']);

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
      return remote >= local;
    }

    int appliedCount = 0;

    // Apply remote updates to local SQLite database
    await db.transaction((txn) async {
      // Ratings
      final remoteRatings = pullResult['ratings'] as List<dynamic>? ?? [];
      for (final r in remoteRatings) {
        if (!await shouldApply(txn, 'ratings', 'movie_id = ? AND is_tv = ?', [
          r['movie_id'],
          r['is_tv'],
        ], r['updated_at'])) {
          continue;
        }
        await txn.insert('ratings', {
          'movie_id': r['movie_id'],
          'is_tv': r['is_tv'],
          'metadata_locale':
              r['metadata_locale'] ?? PrefsService.activeLanguageCode,
          'rating': r['rating'],
          'genre_ids': jsonEncode(_decodeJsonList(r['genre_ids'])),
          'title': r['title'],
          'poster_path': r['poster_path'],
          'backdrop_path': r['backdrop_path'],
          'overview': r['overview'],
          'vote_average': r['vote_average'],
          'release_date': r['release_date'],
          'popularity': r['popularity'],
          'comment': r['comment'],
          'is_spoiler': r['is_spoiler'] ?? 0,
          'is_private': r['is_private'] ?? 0,
          'created_at': r['created_at'],
          'updated_at': r['updated_at'],
          'deleted': r['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Watchlist
      final remoteWatchlist = pullResult['watchlist'] as List<dynamic>? ?? [];
      for (final w in remoteWatchlist) {
        if (!await shouldApply(txn, 'watchlist', 'id = ? AND is_tv = ?', [
          w['id'],
          w['is_tv'],
        ], w['updated_at'])) {
          continue;
        }
        await txn.insert('watchlist', {
          'id': w['id'],
          'is_tv': w['is_tv'],
          'metadata_locale':
              w['metadata_locale'] ?? PrefsService.activeLanguageCode,
          // Compacted legacy tombstones may no longer have catalog metadata.
          // SQLite keeps this legacy column NOT NULL, so retain a harmless
          // placeholder for deleted rows instead of aborting the entire sync.
          'title': w['title'] ?? '',
          'poster_path': w['poster_path'],
          'backdrop_path': w['backdrop_path'],
          'overview': w['overview'],
          'vote_average': w['vote_average'],
          'release_date': w['release_date'],
          'genre_ids': jsonEncode(_decodeJsonList(w['genre_ids'])),
          'created_at': w['created_at'],
          'updated_at': w['updated_at'],
          'deleted': w['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }

      // Favorites
      final remoteFavorites = pullResult['favorites'] as List<dynamic>? ?? [];
      for (final f in remoteFavorites) {
        if (!await shouldApply(txn, 'favorites', 'id = ? AND is_tv = ?', [
          f['id'],
          f['is_tv'],
        ], f['updated_at'])) {
          continue;
        }
        await txn.insert('favorites', {
          'id': f['id'],
          'is_tv': f['is_tv'],
          'metadata_locale':
              f['metadata_locale'] ?? PrefsService.activeLanguageCode,
          // Favorites has the same legacy NOT NULL constraint as watchlist.
          'title': f['title'] ?? '',
          'poster_path': f['poster_path'],
          'backdrop_path': f['backdrop_path'],
          'overview': f['overview'],
          'vote_average': f['vote_average'],
          'release_date': f['release_date'],
          'genre_ids': jsonEncode(_decodeJsonList(f['genre_ids'])),
          'created_at': f['created_at'],
          'updated_at': f['updated_at'],
          'deleted': f['deleted'] ? 1 : 0,
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
          [ws['tv_id'], ws['season_number']],
          ws['updated_at'],
        )) {
          continue;
        }
        await txn.insert('watched_seasons', {
          'tv_id': ws['tv_id'],
          'season_number': ws['season_number'],
          'updated_at': ws['updated_at'],
          'deleted': ws['deleted'] ? 1 : 0,
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
          'created_at': sh['created_at'],
          'updated_at': sh['updated_at'],
          'deleted': sh['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        appliedCount++;
      }
    });

    // Birleşik pull sonrası Top 20 tavanını ve sıra indekslerini toparla.
    // Trim/remap updated_at stamps happen AFTER the main push, so push those
    // favorites in the same sync turn (tombstones + remapped ranks).
    final normalizeStartMs = DateTime.now().millisecondsSinceEpoch;
    final trimmedFavorites = await DatabaseHelper().normalizeFavoritesCap();
    if (trimmedFavorites > 0) {
      appliedCount += trimmedFavorites;
      debugPrint(
        'Sync trimmed $trimmedFavorites favorites over Top 20 cap.',
      );
    }
    await _pushFavoritesTouchedSince(normalizeStartMs);

    // Pull imleci sunucu saatiyle, push imleci cihaz saatiyle ilerler.
    await PrefsService.setLastSyncTime(_overlappingCursor(serverTime));
    PrefsService.invalidateGenreWeights();

    // Invalidate recommendation engine cache and DNA cache
    await _ref?.read(recommendationEngineProvider).invalidateCache();

    if (appliedCount > 0) {
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
      _ref?.read(browseRefreshTriggerProvider.notifier).state++;
    }

    debugPrint(
      "Sync complete. pull cursor: $serverTime, push cursor: ${pushedMax > lastPush ? pushedMax : lastPush}",
    );
    if (_declareLocalReset) {
      _declareLocalReset = false;
    }
    _autoPublishDnaBackground();
  }

  void _autoPublishDnaBackground() {
    final ref = _ref;
    if (ref == null) return;

    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;

    Future.microtask(() async {
      try {
        final userId = auth.user?['id']?.toString();
        final generated = await ref
            .read(tasteDnaServiceProvider)
            .generate(userId: userId);
        final dna = generated.dna;
        final currentHash = generated.hash;
        final lastPublishedHash = await PrefsService.getLastPublishedDnaHash();

        if (currentHash != lastPublishedHash) {
          await _apiService.publishTasteDna(dna.toJson());
          await PrefsService.setLastPublishedDnaHash(currentHash);
          debugPrint("Sync auto-publish DNA succeeded!");
        } else {
          debugPrint("Sync auto-publish DNA skipped (already up to date).");
        }
      } catch (e) {
        debugPrint("Sync auto-publish DNA failed: $e");
      }
    });
  }

  /// Push favorites rows touched at/after [sinceMs] (cap trim tombstones +
  /// remapped ranks) so they leave in the same sync turn as normalize.
  Future<void> _pushFavoritesTouchedSince(int sinceMs) async {
    final db = await DatabaseHelper().database;
    if (db == null) return;

    final rows = await db.query(
      'favorites',
      where: 'updated_at >= ?',
      whereArgs: [sinceMs],
    );
    if (rows.isEmpty) return;

    final payload = <String, dynamic>{
      'metadata_locale': PrefsService.activeLanguageCode,
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

    final applied = await _pushPayloadInChunks(payload);
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

class SyncNotifier extends StateNotifier<SyncStatus> {
  final SyncService _syncService;

  SyncNotifier(this._syncService) : super(SyncStatus.idle);

  Future<void> performSync() async {
    state = SyncStatus.syncing;
    try {
      // Eşzamanlı çağrıları birleştirme sorumluluğu SyncService'tedir. İkinci
      // bir kilit aynı davranışı iki katmanda tutup durum yönetimini karmaşıklaştırıyordu.
      await _syncService.sync();
      state = SyncStatus.success;
    } catch (e) {
      debugPrint("SyncNotifier: Sync failed: $e");
      state = SyncStatus.error;
      rethrow;
    }
  }

  void resetStatus() {
    state = SyncStatus.idle;
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncStatus>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return SyncNotifier(syncService);
});
