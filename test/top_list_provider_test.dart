import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/top_list_provider.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/sync_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'mocks/secure_storage_mock.dart';

class MockSyncService implements SyncService {
  bool syncCalled = false;

  @override
  Future<void> sync() async {
    syncCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  MockAuthNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Movie _movie(int id, {bool isTV = false}) => Movie(
  id: id,
  title: 'Title $id',
  posterPath: '/p$id.jpg',
  overview: 'o',
  voteAverage: 7.0,
  releaseDate: '2020',
  isTV: isTV,
);

void main() {
  setupSecureStorageMock();

  late MockSyncService mockSync;
  late ProviderContainer container;

  ProviderContainer buildContainer({bool authed = true}) {
    return ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => MockAuthNotifier(
            authed
                ? AuthState(accessToken: 'tok', user: {'id': 1})
                : AuthState(),
          ),
        ),
        syncServiceProvider.overrideWithValue(mockSync),
      ],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
    mockSync = MockSyncService();
  });

  tearDown(() => container.dispose());

  group('TopListProvider', () {
    test(
      'load exposes stored favorites and triggers sync when authed',
      () async {
        await PrefsService.saveFavoriteMovies([_movie(1), _movie(2)]);
        container = buildContainer();

        final notifier = container.read(topListProvider(false).notifier);
        await notifier.load();
        await pumpEventQueue(); // constructor'ın tetiklediği load'u da boşalt

        final state = container.read(topListProvider(false));
        expect(state.value?.map((m) => m.id).toList(), [1, 2]);
        expect(mockSync.syncCalled, isTrue);
      },
    );

    test('add appends, dedupes, and enforces the 20 cap', () async {
      container = buildContainer(authed: false);
      final notifier = container.read(topListProvider(false).notifier);
      await notifier.load();
      await pumpEventQueue(); // constructor'ın tetiklediği load'u da boşalt

      expect(await notifier.add(_movie(1)), isTrue);
      // Duplicate rejected.
      expect(await notifier.add(_movie(1)), isFalse);

      for (var id = 2; id <= TopListNotifier.cap; id++) {
        expect(await notifier.add(_movie(id)), isTrue);
      }
      // 21st rejected — list full.
      expect(container.read(topListProvider(false)).value, hasLength(20));
      expect(await notifier.add(_movie(99)), isFalse);
    });

    test('remove drops the item', () async {
      await PrefsService.saveFavoriteMovies([_movie(1), _movie(2), _movie(3)]);
      container = buildContainer();
      final notifier = container.read(topListProvider(false).notifier);
      await notifier.load();
      await pumpEventQueue(); // constructor'ın tetiklediği load'u da boşalt

      await notifier.remove(2);

      expect(
        container.read(topListProvider(false)).value?.map((m) => m.id).toList(),
        [1, 3],
      );
    });

    test('reorder moves an item to the new rank', () async {
      await PrefsService.saveFavoriteMovies([_movie(1), _movie(2), _movie(3)]);
      container = buildContainer();
      final notifier = container.read(topListProvider(false).notifier);
      await notifier.load();
      await pumpEventQueue(); // constructor'ın tetiklediği load'u da boşalt

      // Move #3 (index 2) to the top (ReorderableListView passes newIndex=0).
      await notifier.reorder(2, 0);

      expect(
        container.read(topListProvider(false)).value?.map((m) => m.id).toList(),
        [3, 1, 2],
      );
    });

    test('movie and tv lists are isolated', () async {
      await PrefsService.saveFavoriteMovies([_movie(1)]);
      await PrefsService.saveFavoriteTvShows([_movie(2, isTV: true)]);
      container = buildContainer(authed: false);

      final movies = container.read(topListProvider(false).notifier);
      final shows = container.read(topListProvider(true).notifier);
      await movies.load();
      await shows.load();
      await pumpEventQueue();

      expect(container.read(topListProvider(false)).value?.single.id, 1);
      expect(container.read(topListProvider(true)).value?.single.id, 2);
    });

    test('onboarding merge does not clobber an existing Top 20', () async {
      // Kullanıcının mevcut listesi (5 film).
      await PrefsService.saveFavoriteMovies([
        _movie(1),
        _movie(2),
        _movie(3),
        _movie(4),
        _movie(5),
      ]);

      // Onboarding tekrar çalışır ve 3 seçim gönderir (biri zaten listede).
      await PrefsService.mergeFavoriteMovies([_movie(1), _movie(6), _movie(7)]);

      final result = await PrefsService.getFavoriteMovies();
      expect(result.map((m) => m.id).toList(), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('merge respects the 20 cap', () async {
      final twenty = [for (var id = 1; id <= 20; id++) _movie(id)];
      await PrefsService.saveFavoriteMovies(twenty);

      await PrefsService.mergeFavoriteMovies([_movie(21), _movie(22)]);

      final result = await PrefsService.getFavoriteMovies();
      expect(result, hasLength(20));
      expect(result.every((m) => m.id <= 20), isTrue);
    });
  });
}
