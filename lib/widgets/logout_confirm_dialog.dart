import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

/// Çıkış onayı: varsayılan olarak yerel veri korunur; isteğe bağlı silme kutusu.
Future<void> showLogoutConfirmDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _LogoutConfirmDialog(parentRef: ref),
  );
}

class _LogoutConfirmDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;

  const _LogoutConfirmDialog({required this.parentRef});

  @override
  ConsumerState<_LogoutConfirmDialog> createState() =>
      _LogoutConfirmDialogState();
}

class _LogoutConfirmDialogState extends ConsumerState<_LogoutConfirmDialog> {
  bool _wipeLocalData = false;
  bool _busy = false;

  Future<void> _confirmLogout() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();

    // Oturum hâlâ geçerliyken son değişiklikleri buluta it (best-effort).
    try {
      await widget.parentRef
          .read(syncServiceProvider)
          .sync()
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('Pre-logout sync timed out; continuing logout.');
    } catch (e) {
      debugPrint('Pre-logout sync failed: $e');
    }

    if (!mounted) return;
    Navigator.pop(context);
    await widget.parentRef
        .read(authProvider.notifier)
        .logout(wipeLocalData: _wipeLocalData);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        tr?.get('auth_logout') ?? 'Sign Out',
        style: TextStyle(
          color: c.ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr?.get('auth_logout_confirm') ??
                'Sign out of your account? Your ratings and lists stay on this device.',
            style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _busy
                ? null
                : () => setState(() => _wipeLocalData = !_wipeLocalData),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _wipeLocalData,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _wipeLocalData = v ?? false),
                      activeColor: c.red,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr?.get('auth_logout_wipe_local') ??
                          'Also remove data from this device',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(
            tr?.get('profile_cancel') ?? 'Cancel',
            style: TextStyle(color: c.dim),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _confirmLogout,
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.red,
                  ),
                )
              : Text(
                  tr?.get('auth_logout') ?? 'Sign Out',
                  style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}
