import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'api_service.dart';
import 'providers.dart';
import '../providers/auth_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/swipe_provider.dart';
import '../providers/social_provider.dart';

/// Sunucudan gelen sayısal alanları güvenle int'e çevirir. Paylaşımlı
/// hosting'deki MySQL/PDO, BIGINT kolonları JSON'a STRING olarak yazar
/// (ör. "updated_at":"1783407000000"); doğrudan `as num` cast'i TypeError
/// fırlatır ve sync her seferinde aynı yerde patlar.
int _asInt(Object? v) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

class SyncService {
  final ApiService _apiService;
  final Ref? _ref;
  Future<void>? _syncFuture;

  SyncService(this._apiService, [this._ref]);

  // Core 2-way delta-sync method
  Future<void> sync() async {
    if (_syncFuture != null) {
      debugPrint("Sync already in progress, coalescing request.");
      return _syncFuture;
    }
    _syncFuture = _performSync();
    try {
      await _syncFuture;
    } finally {
      _syncFuture = null;
    }
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
    // Watermark, SELECT'ten ÖNCE alınır: sync sürerken yazılan kayıtlar bir
    // sonraki turda yeniden seçilir (upsert idempotent olduğundan zararsız).
    final pushWatermark = DateTime.now().millisecondsSinceEpoch;
    final db = await DatabaseHelper().database;
    if (db == null) {
      // Web / FLUTTER_TEST mock storage: no SQLite, but cloud handshake still runs.
      debugPrint(
        "Starting sync (mock DB). pull since: $lastPull, push since: $lastPush",
      );
      final pushResult = await _apiService.push(<String, dynamic>{});
      debugPrint("Push complete. Applied changes: ${pushResult['applied']}");
      final pullResult = await _apiService.pull(lastPull);
      final serverTime = _asInt(pullResult['server_time']);
      await PrefsService.setLastSyncTime(serverTime);
      await PrefsService.setLastPushTime(pushWatermark);
      PrefsService.invalidateGenreWeights();
      await _ref?.read(recommendationEngineProvider).invalidateCache();
      debugPrint(
        "Sync complete (mock DB). pull cursor: $serverTime, push cursor: $pushWatermark",
      );
      _autoPublishDnaBackground();
      return;
    }

    debugPrint("Starting sync. pull since: $lastPull, push since: $lastPush");

    // 1. Build and PUSH local changes
    final payload = <String, dynamic>{};

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
            'rating': r['rating'],
            'genre_ids': jsonDecode(r['genre_ids'] as String),
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
            'title': w['title'],
            'poster_path': w['poster_path'],
            'backdrop_path': w['backdrop_path'],
            'overview': w['overview'],
            'vote_average': w['vote_average'],
            'release_date': w['release_date'],
            'genre_ids': jsonDecode(w['genre_ids'] as String),
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
            'title': f['title'],
            'poster_path': f['poster_path'],
            'backdrop_path': f['backdrop_path'],
            'overview': f['overview'],
            'vote_average': f['vote_average'],
            'release_date': f['release_date'],
            'genre_ids': jsonDecode(f['genre_ids'] as String),
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
    final pushResult = await _apiService.push(payload);
    debugPrint("Push complete. Applied changes: ${pushResult['applied']}");

    // 2. PULL remote changes
    final pullResult = await _apiService.pull(lastPull);
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
          'rating': r['rating'],
          'genre_ids': jsonEncode(r['genre_ids']),
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
          'title': w['title'],
          'poster_path': w['poster_path'],
          'backdrop_path': w['backdrop_path'],
          'overview': w['overview'],
          'vote_average': w['vote_average'],
          'release_date': w['release_date'],
          'genre_ids': jsonEncode(w['genre_ids']),
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
          'title': f['title'],
          'poster_path': f['poster_path'],
          'backdrop_path': f['backdrop_path'],
          'overview': f['overview'],
          'vote_average': f['vote_average'],
          'release_date': f['release_date'],
          'genre_ids': jsonEncode(f['genre_ids']),
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

    // Pull imleci sunucu saatiyle, push imleci cihaz saatiyle ilerler.
    await PrefsService.setLastSyncTime(serverTime);
    await PrefsService.setLastPushTime(pushWatermark);
    PrefsService.invalidateGenreWeights();

    // Invalidate recommendation engine cache and DNA cache
    await _ref?.read(recommendationEngineProvider).invalidateCache();

    if (appliedCount > 0) {
      debugPrint(
        "Sync pulled $appliedCount database changes. Invalidating UI providers.",
      );
      _ref?.invalidate(watchlistProvider);
      _ref?.invalidate(statsProvider);
      _ref?.invalidate(swipeProvider);
      _ref?.invalidate(socialProvider);
    }

    debugPrint(
      "Sync complete. pull cursor: $serverTime, push cursor: $pushWatermark",
    );
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
        final dna = await ref
            .read(tasteDnaServiceProvider)
            .generate(userId: userId);

        final cachedData = await PrefsService.getCachedDna();
        final currentHash = cachedData?['hash'];
        final lastPublishedHash = await PrefsService.getLastPublishedDnaHash();

        if (currentHash != null && currentHash != lastPublishedHash) {
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
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return SyncService(apiService, ref);
});

enum SyncStatus { idle, syncing, success, error }

class SyncNotifier extends StateNotifier<SyncStatus> {
  final SyncService _syncService;
  Future<void>? _syncFuture;

  SyncNotifier(this._syncService) : super(SyncStatus.idle);

  Future<void> performSync() async {
    if (_syncFuture != null) {
      return _syncFuture;
    }
    state = SyncStatus.syncing;
    _syncFuture = _syncService.sync();
    try {
      await _syncFuture;
      state = SyncStatus.success;
    } catch (e) {
      debugPrint("SyncNotifier: Sync failed: $e");
      state = SyncStatus.error;
      rethrow;
    } finally {
      _syncFuture = null;
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
