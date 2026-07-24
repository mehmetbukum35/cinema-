import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/screens/search/widgets/filter_chip.dart';
import 'package:ne_izlesem/screens/search/widgets/quick_access.dart';

import 'helpers/widget_test_helpers.dart';

void main() {
  testWidgets('search filter chip exposes state and a 44px touch target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      pumpApp(
        SearchFilterChip(label: 'Netflix', selected: true, onTap: () {}),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = find.byKey(
      const ValueKey('search_filter_touch_target_Netflix'),
    );
    expect(gesture, findsOneWidget);
    final size = tester.getSize(gesture);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    final semanticsFinder = find.byKey(
      const ValueKey('search_filter_semantics_Netflix'),
    );
    expect(semanticsFinder, findsOneWidget);

    final node = tester.getSemantics(semanticsFinder);
    expect(node.label, 'Netflix');
    expect(node.flagsCollection.isButton.toString(), 'true');
    expect(node.flagsCollection.isSelected.toString(), 'Tristate.isTrue');
    semantics.dispose();
  });

  testWidgets('clear history has a descriptive label and 44px touch target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      pumpApp(
        SearchQuickAccess(
          history: const ['Dune'],
          onClearHistory: () {},
          onSearchFromHistory: (_) {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final clear = find.byKey(const ValueKey('clear_search_history_semantics'));
    expect(clear, findsOneWidget);
    final clearNode = tester.getSemantics(clear);
    expect(clearNode.label, contains('Clear search history'));
    final gesture = find.byKey(
      const ValueKey('clear_search_history_touch_target'),
    );
    expect(gesture, findsOneWidget);
    final size = tester.getSize(gesture);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });
}
