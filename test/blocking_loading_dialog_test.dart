import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/widgets/blocking_loading_dialog.dart';

void main() {
  testWidgets('back cannot dismiss loading dialog or pop its parent route', (
    tester,
  ) async {
    final task = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => runWithBlockingLoadingDialog(
                context: context,
                color: Colors.red,
                task: () => task.future,
              ),
              child: const Text('Yükle'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Yükle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Yükle'), findsOneWidget);

    task.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Yükle'), findsOneWidget);
  });
}
