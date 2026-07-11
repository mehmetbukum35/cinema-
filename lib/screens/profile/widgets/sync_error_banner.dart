import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../services/sync_service.dart';
import '../../../theme/app_theme.dart';

/// Eşitleme hatası bandı: veri kaybı olmadığını söyler, tekrar dene sunar.
class SyncErrorBanner extends ConsumerWidget {
  const SyncErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.red.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: c.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr?.get('sync_error_message') ??
                  'Eşitleme başarısız oldu. Değişiklikleriniz bu cihazda güvende.',
              style: TextStyle(
                color: c.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(syncProvider.notifier).performSync().catchError((_) {});
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              tr?.get('sync_retry') ?? 'Tekrar Dene',
              style: TextStyle(
                color: c.gold,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
