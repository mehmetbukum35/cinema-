import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// Hesap silme onayı: geri alınamaz uyarısı + bilinçli onay kutusu.
/// Google Play politikası gereği hesap oluşturulabilen uygulamalarda
/// uygulama içinden kalıcı hesap silme yolu bulunmak zorundadır.
Future<void> showDeleteAccountDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DeleteAccountDialog(parentRef: ref),
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;

  const _DeleteAccountDialog({required this.parentRef});

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _ack = false;
  bool _busy = false;

  Future<void> _confirmDelete() async {
    if (_busy || !_ack) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();

    final tr = AppLocalizations.of(context);
    final ok = await widget.parentRef
        .read(authProvider.notifier)
        .deleteAccount();

    if (!mounted) return;
    // Toast kök Overlay'de yaşar; dialog kapansa da görünür kalır.
    showAppToast(
      context,
      ok
          ? (tr?.get('auth_delete_done') ??
                'Hesabınız ve bulut verileriniz kalıcı olarak silindi.')
          : (tr?.get('auth_err_delete_failed') ??
                'Hesap silinemedi. Lütfen tekrar deneyin.'),
      success: ok,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        tr?.get('auth_delete_account') ?? 'Hesabı Sil',
        style: TextStyle(
          color: c.red,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr?.get('auth_delete_confirm') ??
                'Bu işlem hesabınızı ve tüm bulut verilerinizi kalıcı olarak silecektir. Emin misiniz?',
            style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _busy ? null : () => setState(() => _ack = !_ack),
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
                      value: _ack,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _ack = v ?? false),
                      activeColor: c.red,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr?.get('auth_delete_ack') ??
                          'Bu işlemin geri alınamayacağını anlıyorum.',
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
            tr?.get('profile_cancel') ?? 'Vazgeç',
            style: TextStyle(color: c.dim),
          ),
        ),
        TextButton(
          onPressed: (_busy || !_ack) ? null : _confirmDelete,
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
                  tr?.get('auth_delete_account') ?? 'Hesabı Sil',
                  style: TextStyle(
                    color: _ack ? c.red : c.dim,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }
}
