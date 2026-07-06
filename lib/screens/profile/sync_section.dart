import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/sync_service.dart';
import '../../services/prefs_service.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/swipe_provider.dart';

enum AuthMode { login, register, forgotEmail, forgotCode, forgotReset }

class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  bool _syncing = false;
  String? _syncTimeStr;

  @override
  void initState() {
    super.initState();
    _loadSyncTime();
  }

  Future<void> _loadSyncTime() async {
    final timestamp = await PrefsService.getLastSyncTime();
    if (timestamp == 0) {
      if (mounted) setState(() => _syncTimeStr = null);
      return;
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (mounted) {
      setState(() => _syncTimeStr = "$day.$month $hour:$min");
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    HapticFeedback.lightImpact();
    try {
      await ref.read(syncServiceProvider).sync();
      ref.invalidate(watchlistProvider);
      ref.invalidate(statsProvider);
      ref.invalidate(swipeProvider);
      await _loadSyncTime();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('sync_success') ??
                  'Successfully synced',
            ),
            backgroundColor: context.c.gold,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: context.c.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showAuthSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AuthSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final authState = ref.watch(authProvider);

    if (authState.isAuthenticated) {
      final displayName =
          authState.user?['display_name'] as String? ??
          authState.user?['email'] as String? ??
          '';
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: c.isLight ? Border.all(color: c.border, width: 1) : null,
          boxShadow: c.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.gold.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.cloud_done_rounded,
                    color: c.gold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _syncTimeStr != null
                            ? "${AppLocalizations.of(context)?.get('sync_last') ?? 'Last synced: '}$_syncTimeStr"
                            : AppLocalizations.of(context)?.get('sync_desc') ??
                                  'Cloud sync active',
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _syncing ? null : _runSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.gold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context)?.get('sync_now') ??
                                'Sync Now',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(authProvider.notifier).logout();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: c.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.get('auth_logout') ??
                        'Logout',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Unauthenticated state
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.red.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.cloud_off_rounded, color: c.red, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.get('sync_title') ??
                          'Cloud Sync',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)?.get('sync_desc') ??
                          'Sync your data safely.',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _showAuthSheet(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                AppLocalizations.of(context)?.get('auth_title_login') ??
                    'Sign In',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthSheet extends ConsumerStatefulWidget {
  const AuthSheet({super.key});

  @override
  ConsumerState<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<AuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim();

    bool success = false;
    final notifier = ref.read(authProvider.notifier);
    final authState = ref.read(authProvider);

    if (_mode == AuthMode.login) {
      success = await notifier.login(email, password);
      if (success && mounted) {
        Navigator.pop(context);
      }
    } else if (_mode == AuthMode.register) {
      success = await notifier.register(email, password, displayName: name);
      if (success && mounted) {
        Navigator.pop(context);
      }
    } else if (_mode == AuthMode.forgotEmail) {
      success = await notifier.forgotPassword(email);
      if (success && mounted) {
        setState(() => _mode = AuthMode.forgotCode);
      }
    } else if (_mode == AuthMode.forgotCode) {
      success = await notifier.verifyResetCode(email, code);
      if (success && mounted) {
        setState(() => _mode = AuthMode.forgotReset);
      }
    } else if (_mode == AuthMode.forgotReset) {
      success = await notifier.resetPassword(email, code, password);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('auth_forgot_success_reset') ??
                  'Password reset successfully.',
            ),
          ),
        );
        setState(() => _mode = AuthMode.login);
      }
    }

    if (!success && mounted) {
      final err = authState.error ?? 'Bir hata oluştu';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: context.c.red),
      );
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
                _mode == AuthMode.login
                    ? (AppLocalizations.of(context)?.get('auth_title_login') ??
                          'Sign In')
                    : _mode == AuthMode.register
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_title_register') ??
                          'Sign Up')
                    : (AppLocalizations.of(context)?.get('auth_forgot_title') ??
                          'Forgot Password'),
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _mode == AuthMode.login
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_login_subtitle') ??
                          'Sign in to continue')
                    : _mode == AuthMode.register
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_register_subtitle') ??
                          'Create your account')
                    : _mode == AuthMode.forgotEmail
                    ? (AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_email_desc') ??
                          'Enter email to receive reset code')
                    : _mode == AuthMode.forgotCode
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

              // Input Fields
              if (_mode != AuthMode.forgotCode &&
                  _mode != AuthMode.forgotReset) ...[
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

              if (_mode == AuthMode.register) ...[
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(color: c.ink, fontSize: 14),
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(
                          context,
                        )?.get('auth_display_name_optional') ??
                        'Display Name (optional)',
                    labelStyle: TextStyle(color: c.dim, fontSize: 13),
                    filled: true,
                    fillColor: c.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      color: c.dim,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (_mode == AuthMode.forgotCode) ...[
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

              if (_mode == AuthMode.login ||
                  _mode == AuthMode.register ||
                  _mode == AuthMode.forgotReset) ...[
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  style: TextStyle(color: c.ink, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: _mode == AuthMode.forgotReset
                        ? (AppLocalizations.of(
                                context,
                              )?.get('auth_forgot_label_new_pass') ??
                              'New Password')
                        : (AppLocalizations.of(context)?.get('auth_password') ??
                              'Password'),
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

              // Forgot password link
              if (_mode == AuthMode.login) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _mode = AuthMode.forgotEmail),
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.get('auth_forgot_password_link') ??
                          'Forgot Password?',
                      style: TextStyle(color: c.gold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                          _mode == AuthMode.login
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_button_login') ??
                                    'Login')
                              : _mode == AuthMode.register
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_button_register') ??
                                    'Register')
                              : _mode == AuthMode.forgotEmail
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_btn_send_code') ??
                                    'Send Code')
                              : _mode == AuthMode.forgotCode
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

              // Bottom Toggle Links
              if (_mode == AuthMode.login || _mode == AuthMode.register) ...[
                TextButton(
                  onPressed: () => setState(() {
                    _mode = _mode == AuthMode.login
                        ? AuthMode.register
                        : AuthMode.login;
                    _formKey.currentState?.reset();
                  }),
                  child: Text(
                    _mode == AuthMode.register
                        ? (AppLocalizations.of(
                                context,
                              )?.get('auth_toggle_to_login') ??
                              'Already have an account? Sign In')
                        : (AppLocalizations.of(
                                context,
                              )?.get('auth_toggle_to_register') ??
                              "Don't have an account? Sign Up"),
                    style: TextStyle(color: c.dim, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else ...[
                TextButton(
                  onPressed: () => setState(() {
                    if (_mode == AuthMode.forgotEmail) {
                      _mode = AuthMode.login;
                    } else if (_mode == AuthMode.forgotCode) {
                      _mode = AuthMode.forgotEmail;
                    } else if (_mode == AuthMode.forgotReset) {
                      _mode = AuthMode.forgotCode;
                    }
                    _formKey.currentState?.reset();
                  }),
                  child: Text(
                    AppLocalizations.of(context)?.get('auth_forgot_btn_back') ??
                        'Back',
                    style: TextStyle(color: c.dim, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
