import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';

class ChangePasswordSheet extends StatefulWidget {
  final WidgetRef ref;
  final BuildContext parentContext;

  const ChangePasswordSheet({
    super.key,
    required this.ref,
    required this.parentContext,
  });

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String? _localError;
  bool _isLoading = false;

  @override
  void dispose() {
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tr = AppLocalizations.of(context);
    final oldPass = _oldPasswordCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      setState(() {
        _localError = tr?.get('auth_forgot_err_name_empty') ?? 'Boş alan bırakılamaz.';
      });
      return;
    }

    if (newPass.length < 6) {
      setState(() {
        _localError = tr?.get('change_password_error_short') ?? 'Yeni şifre en az 6 karakter olmalıdır.';
      });
      return;
    }

    if (newPass != confirmPass) {
      setState(() {
        _localError = tr?.get('change_password_error_mismatch') ?? 'Yeni şifreler eşleşmiyor.';
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(widget.parentContext);

    setState(() {
      _localError = null;
      _isLoading = true;
    });

    final success = await widget.ref.read(authProvider.notifier).changePassword(oldPass, newPass);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        // Close the sheet
        Navigator.pop(context);
        
        // Show success snackbar
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr?.get('change_password_success') ?? 'Şifreniz başarıyla değiştirildi. Tekrar giriş yapın.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final authState = widget.ref.read(authProvider);
        setState(() {
          _localError = authState.error != null ? tr?.get(authState.error!) ?? authState.error : 'İşlem başarısız.';
        });
      }
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
          // Handle/Drag bar
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
            tr?.get('change_password_title') ?? 'Şifre Değiştir',
            style: TextStyle(
              color: c.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            tr?.get('change_password_desc') ?? 'Şifreniz değiştirildiğinde tüm cihazlardan çıkış yapılacaktır.',
            style: TextStyle(
              color: c.dim,
              fontSize: 12,
            ),
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
                style: TextStyle(color: c.red, fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Old Password Field
          TextField(
            controller: _oldPasswordCtrl,
            obscureText: _obscureOld,
            decoration: InputDecoration(
              labelText: tr?.get('change_password_old_password') ?? 'Mevcut Şifre',
              labelStyle: TextStyle(color: c.dim, fontSize: 13),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.gold, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureOld ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: c.dim,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureOld = !_obscureOld),
              ),
            ),
            style: TextStyle(color: c.ink, fontSize: 14),
          ),
          const SizedBox(height: 14),

          // New Password Field
          TextField(
            controller: _newPasswordCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: tr?.get('change_password_new_password') ?? 'Yeni Şifre',
              labelStyle: TextStyle(color: c.dim, fontSize: 13),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.gold, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: c.dim,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            style: TextStyle(color: c.ink, fontSize: 14),
          ),
          const SizedBox(height: 14),

          // Confirm New Password Field
          TextField(
            controller: _confirmPasswordCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: tr?.get('change_password_confirm_password') ?? 'Yeni Şifreyi Onayla',
              labelStyle: TextStyle(color: c.dim, fontSize: 13),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.borderSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.gold, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: c.dim,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            style: TextStyle(color: c.ink, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: Colors.black,
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
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    tr?.get('change_password_button') ?? 'Şifreyi Güncelle',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
