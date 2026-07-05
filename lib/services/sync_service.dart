import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'api_service.dart';
import '../providers/auth_provider.dart';

class SyncService {
  final ApiService _apiService;
  Future<void>? _syncFuture;

  SyncService(this._apiService);

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
    final lastSync = await PrefsService.getLastSyncTime();
    final db = await DatabaseHelper().database;
    if (db == null) {
      return; // Silent return if db is mock (e.g. on unsupported platforms/tests)
    }

    debugPrint("Starting sync since timestamp: $lastSync");

    // 1. Build and PUSH local changes
    final payload = <String, dynamic>{};

    // Ratings
    final localRatings = await db.query(
      'ratings',
      where: 'updated_at > ?',
      whereArgs: [lastSync],
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
      whereArgs: [lastSync],
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
      whereArgs: [lastSync],
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
      whereArgs: [lastSync],
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
      whereArgs: [lastSync],
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
    final pullResult = await _apiService.pull(lastSync);
    final serverTime = pullResult['server_time'] as int;

    // Apply remote updates to local SQLite database
    await db.transaction((txn) async {
      // Ratings
      final remoteRatings = pullResult['ratings'] as List<dynamic>? ?? [];
      for (final r in remoteRatings) {
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
          'created_at': r['created_at'],
          'updated_at': r['updated_at'],
          'deleted': r['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Watchlist
      final remoteWatchlist = pullResult['watchlist'] as List<dynamic>? ?? [];
      for (final w in remoteWatchlist) {
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
      }

      // Favorites
      final remoteFavorites = pullResult['favorites'] as List<dynamic>? ?? [];
      for (final f in remoteFavorites) {
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
      }

      // Watched Seasons
      final remoteWatchedSeasons =
          pullResult['watched_seasons'] as List<dynamic>? ?? [];
      for (final ws in remoteWatchedSeasons) {
        await txn.insert('watched_seasons', {
          'tv_id': ws['tv_id'],
          'season_number': ws['season_number'],
          'updated_at': ws['updated_at'],
          'deleted': ws['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Search History
      final remoteSearchHistory =
          pullResult['search_history'] as List<dynamic>? ?? [];
      for (final sh in remoteSearchHistory) {
        await txn.insert('search_history', {
          'query': sh['query'],
          'created_at': sh['created_at'],
          'updated_at': sh['updated_at'],
          'deleted': sh['deleted'] ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // Save final server_time as our new last_sync_time
    await PrefsService.setLastSyncTime(serverTime);
    debugPrint("Sync complete. New lastSync timestamp: $serverTime");
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return SyncService(apiService);
});
