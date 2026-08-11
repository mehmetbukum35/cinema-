import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../services/prefs/library_facade.dart';
import '../services/providers.dart';
import 'auth_provider.dart';
import '../services/sync_service.dart';

/// Kişisel "Top 20" (panteon) listesi. Film ve dizi ayrı listelerdir; ikisi de
/// mevcut `favorites` altyapısında yaşar (is_tv ayrımı, created_at = sıra indeksi).
/// Liste bellek içinde otoritedir: her mutasyon tam listeyi `saveFavorite*` ile
/// yeniden yazar ve arka planda sync'i tetikler (watchlist deseni).
class TopListNotifier extends Notifier<AsyncValue<List<Movie>>> {
  final bool isTV;
  final bool autoLoad;
  final Future<List<Movie>> Function()? _readListOverride;
  final Future<void> Function(List<Movie>)? _writeListOverride;
  Future<void> _persistTail = Future<void>.value();
  int _loadGeneration = 0;
  List<Movie>? _activeList;
  Future<List<Movie>>? _readFuture;

  /// Panteon sınırı: liste en fazla 20 öğe tutar.
  static const cap = PrefsLibraryFacade.favoritesCap;

  TopListNotifier(
    this.isTV, {
    Future<List<Movie>> Function()? readList,
    Future<void> Function(List<Movie>)? writeList,
    this.autoLoad = true,
  }) : _readListOverride = readList,
       _writeListOverride = writeList;

  @override
  AsyncValue<List<Movie>> build() {
    if (autoLoad) unawaited(load());
    return const AsyncValue.loading();
  }

  Future<List<Movie>> _readList() => (_readListOverride ?? _defaultRead)();

  Future<void> _writeList(List<Movie> list) =>
      (_writeListOverride ?? _defaultWrite)(list);

  Future<List<Movie>> _defaultRead() => isTV
      ? PrefsLibraryFacade.getFavoriteTvShows()
      : PrefsLibraryFacade.getFavoriteMovies();

  /// Dil, tear-off anında değil yazma anında okunur — kullanıcı arayüz dilini
  /// değiştirdiğinde bir sonraki kayıt yeni dilin metadata'sıyla gider.
  Future<void> _defaultWrite(List<Movie> list) {
    final locale = ref.read(localeProvider).languageCode;
    return isTV
        ? PrefsLibraryFacade.saveFavoriteTvShows(list, metadataLocale: locale)
        : PrefsLibraryFacade.saveFavoriteMovies(list, metadataLocale: locale);
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    try {
      // Offline-first: yerel liste sync beklenmeden gösterilir, sonra tazelenir
      // (bkz. WatchlistNotifier.load).
      var list = await _read();
      if (ref.mounted && generation == _loadGeneration) {
        _activeList = list;
        state = AsyncValue.data(list);
      }
      if (!ref.mounted || generation != _loadGeneration) return;

      final auth = ref.read(authProvider);
      if (auth.isAuthenticated) {
        try {
          await ref.read(syncProvider.notifier).performSync();
          list = await _read();
          if (ref.mounted && generation == _loadGeneration) {
            _activeList = list;
            state = AsyncValue.data(list);
          }
        } catch (_) {
          // SyncNotifier hata durumunu global olarak yakalar.
        }
      }
    } catch (e, st) {
      if (ref.mounted && generation == _loadGeneration) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Öğeyi listenin SONUNA ekler (en düşük sıra). Zaten varsa veya liste doluysa
  /// `false` döner.
  Future<bool> add(Movie movie) async {
    final base = _activeList ?? state.value ?? await _read();
    final current = _activeList ?? state.value ?? base;
    if (current.any((m) => m.id == movie.id)) return false;
    if (current.length >= cap) return false;
    final newList = [...current, movie];
    _activeList = newList;
    await _persist(newList);
    return true;
  }

  Future<void> remove(int id) async {
    final base = _activeList ?? state.value ?? await _read();
    final current = _activeList ?? state.value ?? base;
    final newList = current.where((m) => m.id != id).toList();
    _activeList = newList;
    await _persist(newList);
  }

  /// ReorderableListView sözleşmesi: newIndex, öğe listeden çıkarılmadan ÖNCEki
  /// konumdur; aşağı taşımada bir azaltılır.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final base = _activeList ?? state.value ?? await _read();
    final current = [...(_activeList ?? state.value ?? base)];
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, current.length - 1);
    if (newIndex == oldIndex) return;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    _activeList = current;
    await _persist(current);
  }

  Future<List<Movie>> _read() {
    _readFuture ??= _readList().whenComplete(() => _readFuture = null);
    return _readFuture!;
  }

  Future<void> _persist(List<Movie> list) async {
    ++_loadGeneration;
    // Optimistic UI: önce bellek, disk yazımı başarısız olursa geri al.
    final prior = state.value;
    _activeList = list;
    if (ref.mounted) state = AsyncValue.data(list);
    final previous = _persistTail;
    final operation = previous.catchError((_) {}).then((_) => _writeList(list));
    _persistTail = operation;
    try {
      await operation;
    } catch (e, st) {
      debugPrint('Top list persist failed, rolling back UI: $e\n$st');
      if (prior != null) {
        _activeList = prior;
        if (ref.mounted) state = AsyncValue.data(prior);
      }
      rethrow;
    }
    // Favori değişti → öneri motorunun bellek önbelleğini (keyword vektörü + oy
    // önbelleği) tazele ki Top 20 düzenlemesi anında önerilere yansısın.
    // (Tür ağırlıkları zaten saveFavorite* içinde invalidate ediliyor.)
    await ref.read(recommendationEngineProvider).invalidateCache();
    ref.read(browseRefreshTriggerProvider.notifier).fire();
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
    NotifierProvider.family<TopListNotifier, AsyncValue<List<Movie>>, bool>(
      TopListNotifier.new,
    );
