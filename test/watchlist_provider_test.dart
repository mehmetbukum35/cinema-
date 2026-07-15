import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/watchlist_provider.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/sync_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'mocks/secure_storage_mock.dart';

class MockSyncService implements SyncService {
  bool syncCalled = false;
  Completer<void> started = Completer<void>();
  Completer<void>? gate;

  @override
  Future<void> sync() async {
    syncCalled = true;
    if (!started.isCompleted) started.complete();
    await gate?.future;
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

void main() {
  setupSecureStorageMock();

  late MockSyncService mockSync;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();

    mockSync = MockSyncService();
  });

  tearDown(() {
    container.dispose();
  });

  group('WatchlistProvider Tests', () {
    test(
      'load watchlist should fetch items and trigger sync if authenticated',
      () async {
        // 1. Arrange: authenticated state override
        container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthNotifier(
                AuthState(accessToken: 'test_access', user: {'id': 1}),
              ),
            ),
            syncServiceProvider.overrideWithValue(mockSync),
          ],
        );

        final movie = Movie(
          id: 101,
          title: 'Watchlist Movie',
          posterPath: '/path.jpg',
          backdropPath: '/back.jpg',
          overview: 'Overview',
          voteAverage: 8.0,
          releaseDate: '2026',
          isTV: false,
        );
        await PrefsService.addToWatchlist(movie);

        // 2. Act
        final notifier = container.read(watchlistProvider.notifier);
        await notifier.load();

        // 3. Assert
        final state = container.read(watchlistProvider);
        expect(state, isNotNull);
        state.when(
          data: (list) {
            expect(list, hasLength(1));
            expect(list[0].id, 101);
          },
          loading: () => fail('Should have loaded data'),
          error: (e, s) => fail('Loaded error: $e'),
        );
        expect(mockSync.syncCalled, isTrue);
      },
    );

    test(
      'should expose local watchlist before authenticated sync completes',
      () async {
        final movie = Movie(
          id: 104,
          title: 'Offline Movie',
          posterPath: '/offline.jpg',
          overview: 'Locally available',
          voteAverage: 7.5,
          isTV: false,
        );
        await PrefsService.addToWatchlist(movie);
        mockSync.gate = Completer<void>();

        container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthNotifier(
                AuthState(accessToken: 'test_access', user: {'id': 1}),
              ),
            ),
            syncServiceProvider.overrideWithValue(mockSync),
          ],
        );

        container.read(watchlistProvider);
        await mockSync.started.future;

        final stateWhileSyncing = container.read(watchlistProvider);
        expect(stateWhileSyncing.hasValue, isTrue);
        expect(stateWhileSyncing.value!.single.id, 104);

        mockSync.gate!.complete();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'add should add movie to state and trigger sync if authenticated',
      () async {
        // 1. Arrange
        container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthNotifier(
                AuthState(accessToken: 'test_access', user: {'id': 1}),
              ),
            ),
            syncServiceProvider.overrideWithValue(mockSync),
          ],
        );

        final movie = Movie(
          id: 102,
          title: 'New Movie',
          posterPath: '/path.jpg',
          backdropPath: '/back.jpg',
          overview: 'Overview',
          voteAverage: 8.0,
          releaseDate: '2026',
          isTV: false,
        );

        final notifier = container.read(watchlistProvider.notifier);
        await notifier.load();
        mockSync.syncCalled = false; // reset after initial load sync

        // 2. Act
        await notifier.add(movie);

        // 3. Assert
        final state = container.read(watchlistProvider);
        state.when(
          data: (list) {
            expect(list.any((m) => m.id == 102), isTrue);
          },
          loading: () => fail('Should not be loading'),
          error: (e, s) => fail('Error: $e'),
        );
        expect(mockSync.syncCalled, isTrue);
      },
    );

    test(
      'remove should remove movie from state and trigger sync if authenticated',
      () async {
        // 1. Arrange
        container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthNotifier(
                AuthState(accessToken: 'test_access', user: {'id': 1}),
              ),
            ),
            syncServiceProvider.overrideWithValue(mockSync),
          ],
        );

        final movie = Movie(
          id: 103,
          title: 'Delete Movie',
          posterPath: '/path.jpg',
          backdropPath: '/back.jpg',
          overview: 'Overview',
          voteAverage: 8.0,
          releaseDate: '2026',
          isTV: false,
        );
        await PrefsService.addToWatchlist(movie);

        final notifier = container.read(watchlistProvider.notifier);
        await notifier.load();
        mockSync.syncCalled = false; // reset

        // 2. Act
        await notifier.remove(103, false);

        // 3. Assert
        final state = container.read(watchlistProvider);
        state.when(
          data: (list) {
            expect(list.any((m) => m.id == 103), isFalse);
          },
          loading: () => fail('Should not be loading'),
          error: (e, s) => fail('Error: $e'),
        );
        expect(mockSync.syncCalled, isTrue);
      },
    );
  });
}
