import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

Future<ConflictResolution?> showAuthConflictDialog(BuildContext context) async {
  return await showDialog<ConflictResolution>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AuthConflictDialog(),
  );
}

class AuthConflictDialog extends StatelessWidget {
  const AuthConflictDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.borderSoft),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr?.get('auth_conflict_title') ?? 'Account Conflict',
              style: TextStyle(
                color: c.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        tr?.get('auth_conflict_desc') ??
            'This device has local data (ratings, lists) that is not yet linked to the account you are signing into — it may have been created as a guest or with another account. "Delete Local Data" will permanently erase it from this device. How would you like to proceed?',
        style: TextStyle(color: c.dim, fontSize: 14, height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop(ConflictResolution.merge);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                tr?.get('auth_conflict_merge') ?? 'Merge with this Account',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop(ConflictResolution.delete);
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                foregroundColor: c.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                tr?.get('auth_conflict_delete') ?? 'Delete Local & Load Cloud',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(
                  context,
                ).pop(null); // returns null which means cancel
              },
              style: TextButton.styleFrom(
                foregroundColor: c.dim,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(tr?.get('auth_conflict_cancel') ?? 'Cancel Login'),
            ),
          ],
        ),
      ],
    );
  }
}
