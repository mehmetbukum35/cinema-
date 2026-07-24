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
}
