import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/services/providers.dart';

/// Sırayla tempolu probe'lar veren bir container kurar. Probe artık
/// constructor'dan değil `offlineProbeProvider`'dan geldiği için test gerçek
/// provider kablolamasını da doğruluyor.
({ProviderContainer container, OfflineNotifier notifier}) makeSubject(
  List<Completer<bool>> probes,
) {
  var call = 0;
  final container = ProviderContainer(
    overrides: [
      offlineProbeProvider.overrideWithValue(() => probes[call++].future),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    notifier: container.read(offlineProvider.notifier),
  );
}

void main() {
  test(
    'older failed connectivity check cannot overwrite newer success',
    () async {
      final probes = <Completer<bool>>[Completer<bool>(), Completer<bool>()];
      final (:container, :notifier) = makeSubject(probes);

      final older = notifier.checkNow();
      final newer = notifier.checkNow();

      probes[1].complete(true);
      await newer;
      expect(container.read(offlineProvider), isFalse);

      probes[0].completeError(TimeoutException('stale timeout'));
      await older;
      expect(container.read(offlineProvider), isFalse);
    },
  );

  test(
    'older successful connectivity check cannot overwrite newer failure',
    () async {
      final probes = <Completer<bool>>[Completer<bool>(), Completer<bool>()];
      final (:container, :notifier) = makeSubject(probes);

      final older = notifier.checkNow();
      final newer = notifier.checkNow();

      probes[1].completeError(TimeoutException('current timeout'));
      await newer;
      expect(container.read(offlineProvider), isTrue);

      probes[0].complete(true);
      await older;
      expect(container.read(offlineProvider), isTrue);
    },
  );
}
