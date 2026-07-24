import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/providers.dart';

void main() {
  test(
    'older failed connectivity check cannot overwrite newer success',
    () async {
      final probes = <Completer<bool>>[Completer<bool>(), Completer<bool>()];
      var call = 0;
      final notifier = OfflineNotifier(
        autoStart: false,
        probe: () => probes[call++].future,
      );
      addTearDown(notifier.dispose);

      final older = notifier.checkNow();
      final newer = notifier.checkNow();

      probes[1].complete(true);
      await newer;
      expect(notifier.state, isFalse);

      probes[0].completeError(TimeoutException('stale timeout'));
      await older;
      expect(notifier.state, isFalse);
    },
  );

  test(
    'older successful connectivity check cannot overwrite newer failure',
    () async {
      final probes = <Completer<bool>>[Completer<bool>(), Completer<bool>()];
      var call = 0;
      final notifier = OfflineNotifier(
        autoStart: false,
        probe: () => probes[call++].future,
      );
      addTearDown(notifier.dispose);

      final older = notifier.checkNow();
      final newer = notifier.checkNow();

      probes[1].completeError(TimeoutException('current timeout'));
      await newer;
      expect(notifier.state, isTrue);

      probes[0].complete(true);
      await older;
      expect(notifier.state, isTrue);
    },
  );
}
