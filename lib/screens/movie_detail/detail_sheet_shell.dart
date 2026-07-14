import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Detay alt sayfasının kasası: sürüklenebilir sheet + blur zemin + tutamaç.
/// İçerik, scroll controller'ı sheet'ten alması gerektiği için
/// [contentBuilder] ile üretilir.
class DetailSheetShell extends StatelessWidget {
  final Widget Function(BuildContext context, ScrollController controller)
  contentBuilder;

  const DetailSheetShell({super.key, required this.contentBuilder});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (ctx, ctrl) {
        final c = ctx.c;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: c.bg.withValues(alpha: c.isLight ? 0.96 : 0.85),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(
                  color: c.isLight
                      ? c.border
                      : Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(child: contentBuilder(ctx, ctrl)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
