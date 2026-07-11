import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

enum _ForgotStep { email, code, reset }

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  ConsumerState<ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  _ForgotStep _step = _ForgotStep.email;
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passCtrl.text;

    final notifier = ref.read(authProvider.notifier);
    bool success = false;

    if (_step == _ForgotStep.email) {
      success = await notifier.forgotPassword(email);
      if (success && mounted) {
        setState(() => _step = _ForgotStep.code);
      }
    } else if (_step == _ForgotStep.code) {
      success = await notifier.verifyResetCode(email, code);
      if (success && mounted) {
        setState(() => _step = _ForgotStep.reset);
      }
    } else if (_step == _ForgotStep.reset) {
      success = await notifier.resetPassword(email, code, password);
      if (success && mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context)?.get('auth_forgot_success_reset') ??
              'Password reset successfully.',
        );
        Navigator.pop(context);
      }
    }

    if (!success && mounted) {
      // SnackBar bu açık sheet'in arkasında kalıyordu; toast üstte görünür.
      final errKey = ref.read(authProvider).error ?? 'auth_err_generic';
      final err = AppLocalizations.of(context)?.get(errKey) ?? errKey;
      showAppToast(context, err, success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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

              // Title
              Text(
                AppLocalizations.of(context)?.get('auth_forgot_title') ??
                    'Forgot Password',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),

              // Subtitle description based on step
              Text(
                _step == _ForgotStep.email
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_email_desc') ??
                          'Enter email to receive reset code')
                    : _step == _ForgotStep.code
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_code_desc') ??
                          'Enter 6-digit verification code')
                    : (AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_reset_desc') ??
                          'Enter your new password'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Input Fields based on step
              if (_step == _ForgotStep.email) ...[
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: c.ink, fontSize: 14),
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context)?.get('auth_email') ??
                        'Email',
                    labelStyle: TextStyle(color: c.dim, fontSize: 13),
                    filled: true,
                    fillColor: c.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: c.dim,
                      size: 18,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty || !val.contains('@')) {
                      return AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_err_email_invalid') ??
                          'Enter valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
              ],

              if (_step == _ForgotStep.code) ...[
                TextFormField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(
                          context,
                        )?.get('auth_forgot_label_code') ??
                        '6-Digit Code',
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
                    if (val == null || val.length != 6) {
                      return AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_err_code_length') ??
                          'Enter 6 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
              ],

              if (_step == _ForgotStep.reset) ...[
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  style: TextStyle(color: c.ink, fontSize: 14),
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(
                          context,
                        )?.get('auth_forgot_label_new_pass') ??
                        'New Password',
                    labelStyle: TextStyle(color: c.dim, fontSize: 13),
                    filled: true,
                    fillColor: c.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: c.dim,
                      size: 18,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: c.dim,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.length < 8) {
                      return AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_err_pass_length') ??
                          'Password must be at least 8 chars';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
              ],

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: authState.loading ? null : _submit,
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
                          _step == _ForgotStep.email
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_btn_send_code') ??
                                    'Send Code')
                              : _step == _ForgotStep.code
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_btn_verify') ??
                                    'Verify Code')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_btn_reset') ??
                                    'Update Password'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Back button link
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (_step == _ForgotStep.email) {
                    Navigator.pop(context);
                  } else if (_step == _ForgotStep.code) {
                    setState(() => _step = _ForgotStep.email);
                  } else if (_step == _ForgotStep.reset) {
                    setState(() => _step = _ForgotStep.code);
                  }
                },
                child: Text(
                  AppLocalizations.of(context)?.get('auth_forgot_btn_back') ??
                      'Back',
                  style: TextStyle(color: c.dim, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
