import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

/// Kayıt sonrası e-posta doğrulama: e-postaya gönderilen 6 haneli kod girilir,
/// doğrulanınca oturum açılır. Başarı/çakışma sonucu AuthResult olarak
/// Navigator.pop ile çağırana döner (çakışma diyaloğunu LoginScreen yönetir).
class VerifyEmailSheet extends ConsumerStatefulWidget {
  final String email;

  /// true ise açılışta kod yeniden gönderilir (girişten gelindiğinde; kayıttan
  /// gelindiğinde kod zaten yeni gönderilmiştir).
  final bool sendCodeOnOpen;

  const VerifyEmailSheet({
    super.key,
    required this.email,
    this.sendCodeOnOpen = false,
  });

  @override
  ConsumerState<VerifyEmailSheet> createState() => _VerifyEmailSheetState();
}

class _VerifyEmailSheetState extends ConsumerState<VerifyEmailSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    if (widget.sendCodeOnOpen) {
      ref.read(authProvider.notifier).resendVerificationCode(widget.email);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final result = await ref
        .read(authProvider.notifier)
        .verifyEmail(widget.email, _codeCtrl.text.trim());
    if (!mounted) return;

    if (result.status == AuthStatus.error) {
      final errKey = result.errorMessage ?? 'auth_err_generic';
      final err = AppLocalizations.of(context)?.get(errKey) ?? errKey;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: context.c.red),
      );
      return;
    }
    Navigator.pop(context, result);
  }

  Future<void> _resend() async {
    HapticFeedback.lightImpact();
    setState(() => _resending = true);
    final ok = await ref
        .read(authProvider.notifier)
        .resendVerificationCode(widget.email);
    if (!mounted) return;
    setState(() => _resending = false);
    final tr = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (tr?.get('auth_verify_resent') ?? 'Kod gönderildi.')
              : (tr?.get('auth_err_forgot_send_failed') ??
                    'Kod gönderilemedi.'),
        ),
        backgroundColor: ok ? null : context.c.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(Icons.mark_email_read_outlined, color: c.gold, size: 40),
              const SizedBox(height: 12),
              Text(
                tr?.get('auth_verify_title') ?? 'E-postanı Doğrula',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (tr?.get('auth_verify_desc') ??
                        '{} adresine gönderilen 6 haneli kodu gir.')
                    .replaceAll('{}', widget.email),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText:
                      tr?.get('auth_forgot_label_code') ??
                      '6 Haneli Doğrulama Kodu',
                  labelStyle: TextStyle(
                    color: c.dim,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: c.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length != 6) {
                    return tr?.get('auth_forgot_err_code_length') ??
                        '6 haneli kodu eksiksiz gir.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: authState.loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: c.red.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: authState.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          tr?.get('auth_verify_btn') ?? 'Doğrula ve Giriş Yap',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: (_resending || authState.loading) ? null : _resend,
                child: Text(
                  tr?.get('auth_verify_resend') ?? 'Kodu Tekrar Gönder',
                  style: TextStyle(color: c.gold, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
