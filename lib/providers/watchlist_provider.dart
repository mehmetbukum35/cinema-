import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';

class WatchlistNotifier extends StateNotifier<AsyncValue<List<Movie>>> {
  final Ref ref;
  WatchlistNotifier(this.ref) : super(const AsyncValue.loading()) {
    Future.microtask(() => load());
  }

  Future<void> load() async {
    try {
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          ref.read(recommendationEngineProvider).invalidateCache(isNegativeChange: false);
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
      final list = await PrefsService.getWatchlist();
      if (mounted) {
        state = AsyncValue.data(list);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> add(Movie movie) async {
    try {
      await PrefsService.addToWatchlist(movie);
      if (mounted) {
        state.whenData((list) {
          if (!list.any((m) => m.id == movie.id && m.isTV == movie.isTV)) {
            state = AsyncValue.data([movie, ...list]);
          }
        });
      }

      // Background push sync
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncServiceProvider).sync().catchError((_) {});
      }
    } catch (e) {
      // Keep state intact
    }
  }

  Future<void> remove(int id, bool isTV) async {
    try {
      await PrefsService.removeFromWatchlist(id, isTV);
      if (mounted) {
        state.whenData((list) {
          state = AsyncValue.data(
            list.where((m) => !(m.id == id && m.isTV == isTV)).toList(),
          );
        });
      }

      // Background push sync
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        ref.read(syncServiceProvider).sync().catchError((_) {});
      }
    } catch (e) {
      // Keep state intact
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

  Future<void> load() async {
    try {
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
        } catch (e) {
          // SyncNotifier captures the error state globally
        }
      }
      final stats = await PrefsService.getStats();
      if (mounted) {
        state = AsyncValue.data(stats);
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
