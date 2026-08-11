import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/notification_service.dart';
import '../services/prefs/library_facade.dart';
import '../services/providers.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';

class WatchlistNotifier extends Notifier<AsyncValue<List<Movie>>> {
  final Future<List<Movie>> Function() _readWatchlist;
  final bool autoLoad;
  int _loadGeneration = 0;
  Future<void> _persistTail = Future<void>.value();

  WatchlistNotifier({
    Future<List<Movie>> Function()? readWatchlist,
    this.autoLoad = true,
  }) : _readWatchlist = readWatchlist ?? PrefsLibraryFacade.getWatchlist;

  @override
  AsyncValue<List<Movie>> build() {
    if (autoLoad) unawaited(load());
    return const AsyncValue.loading();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    try {
      // Offline-first: yerel liste sync beklenmeden gösterilir — yavaş ağda
      // kullanıcı cihazında hazır duran veriye 20 sn spinner arkasından
      // bakmasın. Sync bittiğinde liste yeniden okunup tazelenir.
      var list = await _readWatchlist();
      if (ref.mounted && generation == _loadGeneration) {
        state = AsyncValue.data(list);
      }
      if (!ref.mounted || generation != _loadGeneration) return;

      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          // Not: recommendation cache'i sync'in kendisi zaten invalidate
          // ediyor; buradaki ikinci çağrı kaldırıldı.
          list = await _readWatchlist();
          if (ref.mounted && generation == _loadGeneration) {
            state = AsyncValue.data(list);
          }
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
      if (!ref.mounted || generation != _loadGeneration) return;

      // Çıkış hatırlatıcılarını listeyle hizala (başka cihazdan sync ile
      // gelen ekleme/çıkarmalar dahil). Best-effort; akışı bloklamaz.
      NotificationService.instance
          .syncReleaseReminders(list)
          .catchError((_) {});
    } catch (e, st) {
      if (ref.mounted && generation == _loadGeneration) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<bool> add(Movie movie) async {
    final generation = ++_loadGeneration;
    try {
      final previous = _persistTail;
      final operation = previous.catchError((_) {}).then((_) async {
        if (!ref.mounted || generation != _loadGeneration) return;
        await PrefsLibraryFacade.addToWatchlist(
          movie,
          metadataLocale: ref.read(localeProvider).languageCode,
        );
      });
      _persistTail = operation;
      await operation;
      if (!ref.mounted || generation != _loadGeneration) return true;
      // state.value üzerine yama değil: eşzamanlı add/remove sonrası DB'den oku.
      // (load() için enjekte edilen _readWatchlist değil — o stale-load testine
      // bağlanır; mutasyonlar her zaman gerçek library facade'e yazar.)
      state = AsyncValue.data(await PrefsLibraryFacade.getWatchlist());

      // Henüz çıkmadıysa çıkış gününe hatırlatıcı planla (best-effort)
      try {
        NotificationService.instance
            .scheduleReleaseReminder(movie)
            .catchError((_) {});
      } catch (e) {
        debugPrint('Failed to schedule release reminder: $e');
      }

      // Background push sync
      try {
        final auth = ref.read(authProvider);
        if (auth.isAuthenticated) {
          ref.read(syncProvider.notifier).performSync().catchError((e) {
            debugPrint('Background sync failed on watchlist add: $e');
          });
        }
      } catch (e) {
        debugPrint('Background sync trigger failed on watchlist add: $e');
      }
      return true;
    } catch (e, st) {
      debugPrint('Failed to add watchlist item: $e\n$st');
      return false;
    }
  }

  Future<bool> remove(int id, bool isTV) async {
    final generation = ++_loadGeneration;
    try {
      final previous = _persistTail;
      final operation = previous.catchError((_) {}).then((_) async {
        if (!ref.mounted || generation != _loadGeneration) return;
        await PrefsLibraryFacade.removeFromWatchlist(id, isTV);
      });
      _persistTail = operation;
      await operation;
      if (!ref.mounted || generation != _loadGeneration) return true;
      state = AsyncValue.data(await PrefsLibraryFacade.getWatchlist());

      // Planlanmış çıkış hatırlatıcısını iptal et (best-effort)
      try {
        NotificationService.instance
            .cancelReleaseReminder(id, isTV)
            .catchError((_) {});
      } catch (e) {
        debugPrint('Failed to cancel release reminder: $e');
      }

      // Background push sync
      try {
        final auth = ref.read(authProvider);
        if (auth.isAuthenticated) {
          ref.read(syncProvider.notifier).performSync().catchError((e) {
            debugPrint('Background sync failed on watchlist remove: $e');
          });
        }
      } catch (e) {
        debugPrint('Background sync trigger failed on watchlist remove: $e');
      }
      return true;
    } catch (e, st) {
      debugPrint('Failed to remove watchlist item: $e\n$st');
      return false;
    }
  }
}

final watchlistProvider =
    NotifierProvider<WatchlistNotifier, AsyncValue<List<Movie>>>(
      WatchlistNotifier.new,
    );

class StatsNotifier extends Notifier<AsyncValue<Map<String, dynamic>>> {
  final Future<Map<String, dynamic>> Function() _readStats;
  final bool autoLoad;
  int _loadGeneration = 0;

  StatsNotifier({
    Future<Map<String, dynamic>> Function()? readStats,
    this.autoLoad = true,
  }) : _readStats = readStats ?? PrefsLibraryFacade.getStats;

  @override
  AsyncValue<Map<String, dynamic>> build() {
    if (autoLoad) Future.microtask(load);
    return const AsyncValue.loading();
  }

  /// [skipSync] true ise yalnızca yerel istatistikler yenilenir; sunucu sync'i
  /// tetiklenmez. Yüksek frekanslı çağrılarda (ör. her swipe sonrası) kullanılır —
  /// swipe akışı zaten kendi debounce'lu sync'ini planlıyor.
  Future<void> load({bool skipSync = false}) async {
    final generation = ++_loadGeneration;
    try {
      // Offline-first: yerel istatistikler sync beklenmeden gösterilir;
      // sync bitince yeniden hesaplanıp tazelenir (bkz. WatchlistNotifier.load).
      var stats = await _readStats();
      if (ref.mounted && generation == _loadGeneration) {
        state = AsyncValue.data(stats);
      }
      if (!ref.mounted || generation != _loadGeneration) return;

      final auth = ref.read(authProvider);
      if (!skipSync && auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          stats = await _readStats();
          if (ref.mounted && generation == _loadGeneration) {
            state = AsyncValue.data(stats);
          }
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
    } catch (e, st) {
      if (ref.mounted && generation == _loadGeneration) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

final statsProvider =
    NotifierProvider<StatsNotifier, AsyncValue<Map<String, dynamic>>>(
      StatsNotifier.new,
    );
