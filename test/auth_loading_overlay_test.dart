import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/widgets/auth_loading_overlay.dart';

void main() {
  testWidgets(
    'hidden auth overlay does not block interactions after fading out',
    (tester) async {
      var visible = true;
      var taps = 0;
      late StateSetter update;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                      child: const ColoredBox(color: Colors.white),
                    ),
                  ),
                  AuthLoadingOverlay(
                    key: const Key('auth-overlay'),
                    visible: visible,
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(const Offset(20, 20));
      expect(taps, 0);

      update(() => visible = false);
      await tester.pump();

      // Kapanış animasyonu devam ederken dahi saydamlaşan katman dokunmayı
      // yutmamalı.
      await tester.tapAt(const Offset(20, 20));
      expect(taps, 1);

      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byKey(const Key('auth-overlay')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    },
  );
}
