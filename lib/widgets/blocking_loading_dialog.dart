import 'dart:async';

import 'package:flutter/material.dart';

/// Runs [task] while showing a loading route that cannot be dismissed by the
/// system back action. The captured dialog navigator is used so completion
/// can never pop an unrelated route.
Future<T> runWithBlockingLoadingDialog<T>({
  required BuildContext context,
  required Color color,
  required Future<T> Function() task,
}) async {
  final shown = Completer<BuildContext>();
  final dialogClosed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      if (!shown.isCompleted) shown.complete(dialogContext);
      return PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(color: color)),
      );
    },
  );

  final dialogContext = await shown.future;
  try {
    return await task();
  } finally {
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
      await dialogClosed;
    }
  }
}
