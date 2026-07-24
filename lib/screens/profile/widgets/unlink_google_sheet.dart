import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';

class UnlinkGoogleSheet extends StatefulWidget {
  final WidgetRef ref;

  const UnlinkGoogleSheet({super.key, required this.ref});

  @override
  State<UnlinkGoogleSheet> createState() => _UnlinkGoogleSheetState();
}

class _UnlinkGoogleSheetState extends State<UnlinkGoogleSheet> {
  final _passwordCtrl = TextEditingController();
  String? _localError;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tr = AppLocalizations.of(context);
    if (_passwordCtrl.text.length < 8) {
      setState(() {
        _localError =
            tr?.get('auth_forgot_err_pass_length') ??
            'Password must be at least 8 characters.';
      });
      return;
    }

    setState(() {
      _localError = null;
      _isLoading = true;
    });

    final success = await widget.ref
        .read(authProvider.notifier)
        .unlinkGoogleWithReauth(_passwordCtrl.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Toast kök Overlay'de yaşar; sheet kapansa da klavyenin üstünde
      // görünür kalır.
      showAppToast(
        context,
        tr?.get('google_unlink_success') ??
            'Google hesabı bağlantısı kaldırıldı.',
      );
      Navigator.pop(context);
    } else {
      final authState = widget.ref.read(authProvider);
      setState(() {
        _localError = authState.error != null
            ? tr?.get(authState.error!) ?? authState.error
            : tr?.get('auth_err_google_unlink_failed') ?? 'İşlem başarısız.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.borderSoft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            tr?.get('google_unlink_title') ?? 'Google Bağlantısını Kaldır',
            style: TextStyle(
              color: c.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            tr?.get('google_unlink_reauth_desc') ??
                'Reauthenticate your Google account to continue.',
            style: TextStyle(color: c.dim, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_localError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                _localError!,
                style: TextStyle(
                  color: c.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText:
                  tr?.get('auth_unlink_new_password') ?? 'New account password',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    tr?.get('google_unlink_button') ?? 'Bağlantıyı Kaldır',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
