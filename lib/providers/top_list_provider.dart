import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';

/// Kişisel "Top 20" (panteon) listesi. Film ve dizi ayrı listelerdir; ikisi de
/// mevcut `favorites` altyapısında yaşar (is_tv ayrımı, created_at = sıra indeksi).
/// Liste bellek içinde otoritedir: her mutasyon tam listeyi `saveFavorite*` ile
/// yeniden yazar ve arka planda sync'i tetikler (watchlist deseni).
class TopListNotifier extends StateNotifier<AsyncValue<List<Movie>>> {
  final Ref ref;
  final bool isTV;

  /// Panteon sınırı: liste en fazla 20 öğe tutar.
  static const cap = PrefsService.favoritesCap;

  TopListNotifier(this.ref, this.isTV) : super(const AsyncValue.loading()) {
    Future.microtask(load);
  }

  Future<void> load() async {
    try {
      // Offline-first: yerel liste sync beklenmeden gösterilir, sonra tazelenir
      // (bkz. WatchlistNotifier.load).
      var list = await _read();
      if (mounted) state = AsyncValue.data(list);

      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          list = await _read();
          if (mounted) state = AsyncValue.data(list);
        } catch (_) {
          // SyncNotifier hata durumunu global olarak yakalar.
        }
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Öğeyi listenin SONUNA ekler (en düşük sıra). Zaten varsa veya liste doluysa
  /// `false` döner.
  Future<bool> add(Movie movie) async {
    final current = state.value ?? const <Movie>[];
    if (current.any((m) => m.id == movie.id)) return false;
    if (current.length >= cap) return false;
    await _persist([...current, movie]);
    return true;
  }

  Future<void> remove(int id) async {
    final current = state.value ?? const <Movie>[];
    await _persist(current.where((m) => m.id != id).toList());
  }

  /// ReorderableListView sözleşmesi: newIndex, öğe listeden çıkarılmadan ÖNCEki
  /// konumdur; aşağı taşımada bir azaltılır.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = [...(state.value ?? const <Movie>[])];
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, current.length - 1);
    if (newIndex == oldIndex) return;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await _persist(current);
  }

  Future<List<Movie>> _read() => isTV
      ? PrefsService.getFavoriteTvShows()
      : PrefsService.getFavoriteMovies();

  Future<void> _persist(List<Movie> list) async {
    if (mounted) state = AsyncValue.data(list);
    if (isTV) {
      await PrefsService.saveFavoriteTvShows(list);
    } else {
      await PrefsService.saveFavoriteMovies(list);
    }
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      ref.read(syncProvider.notifier).performSync().catchError((e) {
        debugPrint('Background sync failed on top-list change: $e');
      });
    }
  }
}

/// `isTV` ile parametrelenmiş aile: `topListProvider(false)` film, `(true)` dizi.
final topListProvider =
    StateNotifierProvider.family<
      TopListNotifier,
      AsyncValue<List<Movie>>,
      bool
    >((ref, isTV) => TopListNotifier(ref, isTV));
