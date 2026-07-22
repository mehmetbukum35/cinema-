import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/movie.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';

class WatchlistNotifier extends StateNotifier<AsyncValue<List<Movie>>> {
  final Ref ref;
  final Future<List<Movie>> Function() _readWatchlist;
  int _loadGeneration = 0;

  WatchlistNotifier(
    this.ref, {
    Future<List<Movie>> Function()? readWatchlist,
    bool autoLoad = true,
  }) : _readWatchlist = readWatchlist ?? PrefsService.getWatchlist,
       super(const AsyncValue.loading()) {
    if (autoLoad) unawaited(load());
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    try {
      // Offline-first: yerel liste sync beklenmeden gösterilir — yavaş ağda
      // kullanıcı cihazında hazır duran veriye 20 sn spinner arkasından
      // bakmasın. Sync bittiğinde liste yeniden okunup tazelenir.
      var list = await _readWatchlist();
      if (mounted && generation == _loadGeneration) {
        state = AsyncValue.data(list);
      }
      if (!mounted || generation != _loadGeneration) return;

      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          // Not: recommendation cache'i sync'in kendisi zaten invalidate
          // ediyor; buradaki ikinci çağrı kaldırıldı.
          list = await _readWatchlist();
          if (mounted && generation == _loadGeneration) {
            state = AsyncValue.data(list);
          }
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
      if (!mounted || generation != _loadGeneration) return;

      // Çıkış hatırlatıcılarını listeyle hizala (başka cihazdan sync ile
      // gelen ekleme/çıkarmalar dahil). Best-effort; akışı bloklamaz.
      NotificationService.instance
          .syncReleaseReminders(list)
          .catchError((_) {});
    } catch (e, st) {
      if (mounted && generation == _loadGeneration) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<bool> add(Movie movie) async {
    ++_loadGeneration;
    try {
      await PrefsService.addToWatchlist(movie);
      if (mounted) {
        final list = state.value ?? await PrefsService.getWatchlist();
        if (!list.any((m) => m.id == movie.id && m.isTV == movie.isTV)) {
          state = AsyncValue.data([movie, ...list]);
        } else {
          state = AsyncValue.data(list);
        }
      }

      // Henüz çıkmadıysa çıkış gününe hatırlatıcı planla (best-effort)
      NotificationService.instance
          .scheduleReleaseReminder(movie)
          .catchError((_) {});

      // Background push sync
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncProvider.notifier).performSync().catchError((e) {
          debugPrint('Background sync failed on watchlist add: $e');
        });
      }
      return true;
    } catch (e) {
      debugPrint('Failed to add watchlist item: $e');
      return false;
    }
  }

  Future<bool> remove(int id, bool isTV) async {
    ++_loadGeneration;
    try {
      await PrefsService.removeFromWatchlist(id, isTV);
      if (mounted) {
        final list = state.value ?? await PrefsService.getWatchlist();
        state = AsyncValue.data(
          list.where((m) => !(m.id == id && m.isTV == isTV)).toList(),
        );
      }

      // Planlanmış çıkış hatırlatıcısını iptal et (best-effort)
      NotificationService.instance
          .cancelReleaseReminder(id, isTV)
          .catchError((_) {});

      // Background push sync
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncProvider.notifier).performSync().catchError((e) {
          debugPrint('Background sync failed on watchlist remove: $e');
        });
      }
      return true;
    } catch (e) {
      debugPrint('Failed to remove watchlist item: $e');
      return false;
    }
  }
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, AsyncValue<List<Movie>>>((ref) {
      return WatchlistNotifier(ref);
    });

class StatsNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final Ref ref;
  StatsNotifier(this.ref) : super(const AsyncValue.loading()) {
    Future.microtask(() => load());
  }

  /// [skipSync] true ise yalnızca yerel istatistikler yenilenir; sunucu sync'i
  /// tetiklenmez. Yüksek frekanslı çağrılarda (ör. her swipe sonrası) kullanılır —
  /// swipe akışı zaten kendi debounce'lu sync'ini planlıyor.
  Future<void> load({bool skipSync = false}) async {
    try {
      // Offline-first: yerel istatistikler sync beklenmeden gösterilir;
      // sync bitince yeniden hesaplanıp tazelenir (bkz. WatchlistNotifier.load).
      var stats = await PrefsService.getStats();
      if (mounted) {
        state = AsyncValue.data(stats);
      }

      final auth = ref.read(authProvider);
      if (!skipSync && auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          stats = await PrefsService.getStats();
          if (mounted) {
            state = AsyncValue.data(stats);
          }
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

final statsProvider =
    StateNotifierProvider<StatsNotifier, AsyncValue<Map<String, dynamic>>>((
      ref,
    ) {
      return StatsNotifier(ref);
    });
