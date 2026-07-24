import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/notification_service.dart';

void main() {
  test('release reminder mutations preserve invocation order', () async {
    final service = NotificationService.instance;
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final olderSync = service.debugEnqueueReminderOperation(() async {
      events.add('old-sync-start');
      firstStarted.complete();
      await releaseFirst.future;
      events.add('old-sync-end');
    });
    await firstStarted.future;

    final newerRemoval = service.debugEnqueueReminderOperation(() async {
      events.add('new-remove');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['old-sync-start']);

    releaseFirst.complete();
    await Future.wait([olderSync, newerRemoval]);

    expect(events, ['old-sync-start', 'old-sync-end', 'new-remove']);
  });

  test('failed reminder mutation does not block the next mutation', () async {
    final service = NotificationService.instance;
    var nextRan = false;

    final failed = service.debugEnqueueReminderOperation(
      () => Future<void>.error(StateError('schedule failed')),
    );
    final next = service.debugEnqueueReminderOperation(() async {
      nextRan = true;
    });

    await expectLater(failed, throwsStateError);
    await next;
    expect(nextRan, isTrue);
  });
}
