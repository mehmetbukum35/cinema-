import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// iOS (iPad ve iOS 26+) paylaşım sayfası için kaynak dikdörtgen ister;
/// [anchorContext] paylaş butonunun build context'i olmalı.
Rect? sharePositionOriginFrom(BuildContext anchorContext) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final origin = box.localToGlobal(Offset.zero) & box.size;
  if (origin.width <= 0 || origin.height <= 0) return null;
  return origin;
}

Future<void> shareMessage({
  required BuildContext context,
  BuildContext? anchorContext,
  Rect? sharePositionOrigin,
  required String message,
  String? failureMessage,
}) async {
  final shareOrigin =
      sharePositionOrigin ??
      (anchorContext != null ? sharePositionOriginFrom(anchorContext) : null);
  try {
    await Share.share(message, sharePositionOrigin: shareOrigin);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failureMessage ?? 'Paylaşım açılamadı. Lütfen tekrar deneyin.',
        ),
      ),
    );
  }
}

Future<void> shareFiles({
  required BuildContext context,
  BuildContext? anchorContext,
  Rect? sharePositionOrigin,
  required List<XFile> files,
  String? text,
  String? failureMessage,
}) async {
  final shareOrigin =
      sharePositionOrigin ??
      (anchorContext != null ? sharePositionOriginFrom(anchorContext) : null);
  try {
    await Share.shareXFiles(
      files,
      text: text,
      sharePositionOrigin: shareOrigin,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failureMessage ?? 'Paylaşım açılamadı. Lütfen tekrar deneyin.',
        ),
      ),
    );
  }
}
