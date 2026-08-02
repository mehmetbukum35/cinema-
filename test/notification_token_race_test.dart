import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/notification_service.dart';

void main() {
  test('logout unregister wins over an in-flight token registration', () async {
    final service = NotificationService.instance;
    final registerStarted = Completer<void>();
    final releaseRegister = Completer<void>();
    final events = <String>[];

    service.debugSetTokenHandlers(
      getToken: () async => 'device-token',
      register: (token) async {
        events.add('register:$token');
        registerStarted.complete();
        await releaseRegister.future;
      },
      unregister: (token) async {
        events.add('unregister:$token');
      },
    );
    addTearDown(() {
      service.debugSetTokenHandlers();
    });

    final registering = service.registerToken();
    await registerStarted.future;

    final unregistering = service.unregisterToken();
    releaseRegister.complete();
    await Future.wait([registering, unregistering]);

    expect(events, ['register:device-token', 'unregister:device-token']);

    await service.debugHandleTokenRefresh('new-token-after-logout');
    expect(events, ['register:device-token', 'unregister:device-token']);
  });

  test('logout cancels registration while token lookup is pending', () async {
    final service = NotificationService.instance;
    final pendingLookup = Completer<String?>();
    final events = <String>[];
    var lookupCount = 0;

    service.debugSetTokenHandlers(
      getToken: () {
        lookupCount++;
        return lookupCount == 1
            ? pendingLookup.future
            : Future<String?>.value('device-token');
      },
      register: (token) async {
        events.add('register:$token');
      },
      unregister: (token) async {
        events.add('unregister:$token');
      },
    );
    addTearDown(() {
      service.debugSetTokenHandlers();
    });

    final registering = service.registerToken();
    await Future<void>.delayed(Duration.zero);
    final unregistering = service.unregisterToken();

    pendingLookup.complete('stale-device-token');
    await Future.wait([registering, unregistering]);

    expect(events, ['unregister:device-token']);
  });

  test(
    'a superseded registerToken call does not send its stale token',
    () async {
      final service = NotificationService.instance;
      final firstLookup = Completer<String?>();
      final events = <String>[];
      var lookups = 0;

      service.debugSetTokenHandlers(
        getToken: () {
          lookups++;
          return lookups == 1
              ? firstLookup.future
              : Future<String?>.value('current-token');
        },
        register: (token) async {
          events.add('register:$token');
        },
      );
      addTearDown(() {
        service.debugSetTokenHandlers();
      });

      final first = service.registerToken();
      await Future<void>.delayed(Duration.zero);
      final second = service.registerToken();

      firstLookup.complete('stale-token');
      await Future.wait([first, second]);

      expect(events, ['register:current-token']);
    },
  );

  test('unregister without a token skips the API call', () async {
    final service = NotificationService.instance;
    final events = <String>[];

    service.debugSetTokenHandlers(
      getToken: () async => null,
      unregister: (token) async {
        events.add('unregister:$token');
      },
    );
    addTearDown(() {
      service.debugSetTokenHandlers();
    });

    await service.unregisterToken();

    expect(events, isEmpty);
  });

  test('a failed token operation does not block the next one', () async {
    final service = NotificationService.instance;
    final events = <String>[];

    service.debugSetTokenHandlers(
      getToken: () async => 'device-token',
      register: (token) async => throw StateError('network down'),
      unregister: (token) async {
        events.add('unregister:$token');
      },
    );
    addTearDown(() {
      service.debugSetTokenHandlers();
    });

    await service.registerToken();
    await service.unregisterToken();

    expect(events, ['unregister:device-token']);
  });

  group('invalidateLocalToken', () {
    test('deletes the installation token', () async {
      final service = NotificationService.instance;
      final events = <String>[];

      service.debugSetTokenHandlers(getToken: () async => 'device-token');
      service.debugSetDeleteTokenHandler(() async {
        events.add('delete');
      });
      addTearDown(() {
        service.debugSetTokenHandlers();
        service.debugSetDeleteTokenHandler(null);
      });

      await service.invalidateLocalToken();

      expect(events, ['delete']);
    });

    test('a later token refresh cannot re-register the device', () async {
      final service = NotificationService.instance;
      final events = <String>[];

      service.debugSetTokenHandlers(
        getToken: () async => 'device-token',
        register: (token) async {
          events.add('register:$token');
        },
      );
      service.debugSetDeleteTokenHandler(() async {
        events.add('delete');
      });
      addTearDown(() {
        service.debugSetTokenHandlers();
        service.debugSetDeleteTokenHandler(null);
      });

      await service.registerToken();
      expect(events, ['register:device-token']);

      // Refresh token reddedildikten sonraki yol: token geçersiz kılınır ve
      // FCM'in ürettiği yeni token sunucuya geri gitmemelidir.
      await service.invalidateLocalToken();
      await service.debugHandleTokenRefresh('token-after-invalidate');

      expect(events, ['register:device-token', 'delete']);
    });

    test('registration stays disabled when the delete call fails', () async {
      final service = NotificationService.instance;
      final events = <String>[];

      service.debugSetTokenHandlers(
        getToken: () async => 'device-token',
        register: (token) async {
          events.add('register:$token');
        },
      );
      service.debugSetDeleteTokenHandler(
        () async => throw StateError('firebase unavailable'),
      );
      addTearDown(() {
        service.debugSetTokenHandlers();
        service.debugSetDeleteTokenHandler(null);
      });

      await expectLater(service.invalidateLocalToken(), completes);
      await service.debugHandleTokenRefresh('token-after-failed-delete');

      expect(events, isEmpty);
    });
  });
}
