import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/app_config.dart';
import '../services/localization_service.dart';
import '../widgets/auth_conflict_dialog.dart';
import '../widgets/auth_loading_overlay.dart';
import '../widgets/forgot_password_sheet.dart';
import '../widgets/verify_email_sheet.dart';

/// Giriş + Kayıt ekranı (tek ekranda mod değiştirir).
/// Mevcut akışı bozmaz; istediğin yerden (ör. Profil) buraya yönlendir:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    final result = _isRegister
        ? await notifier.register(
            _emailCtrl.text,
            _passCtrl.text,
            displayName: _nameCtrl.text.trim(),
          )
        : await notifier.login(_emailCtrl.text, _passCtrl.text);
    // Kayıt yolu kodu zaten gönderdi; girişte (doğrulanmamış hesap) kodun
    // doğrulama ekranı açılırken yeniden gönderilmesi gerekir.
    await _handleAuthResult(result, verificationCodeSent: _isRegister);
  }

  Future<void> _googleSignIn() async {
    final result = await ref.read(authProvider.notifier).signInWithGoogle();
    await _handleAuthResult(result);
  }

  /// Başarı/çakışma/doğrulama sonucunu tek yerden işler (e-posta ve Google ortak).
  Future<void> _handleAuthResult(
    AuthResult result, {
    bool verificationCodeSent = false,
  }) async {
    if (!mounted) return;
    if (result.status == AuthStatus.pendingVerification) {
      // E-posta doğrulanmadan oturum açılmaz: kod giriş ekranını aç. Ekran
      // doğrulama sonucunu (başarı/çakışma) AuthResult olarak geri verir.
      // Kapatılabilir: e-posta hiç gelmezse kullanıcı sıkışmasın (tekrar
      // giriş denediğinde ekran yeniden açılır).
      final verifyResult = await showModalBottomSheet<AuthResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => VerifyEmailSheet(
          email: _emailCtrl.text.trim().toLowerCase(),
          sendCodeOnOpen: !verificationCodeSent,
        ),
      );
      if (verifyResult != null && mounted) {
        await _handleAuthResult(verifyResult);
      }
    } else if (result.status == AuthStatus.success) {
      Navigator.of(context).pop();
    } else if (result.status == AuthStatus.conflict) {
      final resolution = await showAuthConflictDialog(context);
      if (resolution != null && mounted) {
        await ref
            .read(authProvider.notifier)
            .completeLogin(
              user: result.user!,
              tokens: result.tokens!,
              resolution: resolution,
            );
        if (mounted) Navigator.of(context).pop();
      } else {
        // İptal: sunucunun çoktan verdiği token çifti kullanılmayacak →
        // sunucuda iptal et ki yetim refresh token kalmasın.
        await ref.read(authProvider.notifier).cancelPendingLogin(result.tokens);
      }
    }
    // error → auth.error zaten ekranda gösteriliyor; cancelled → sessiz.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(
              _isRegister
                  ? (AppLocalizations.of(context)?.get('auth_title_register') ??
                        'Sign Up')
                  : (AppLocalizations.of(context)?.get('auth_title_login') ??
                        'Sign In'),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.movie_outlined, size: 56, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(
                          _isRegister
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_register_subtitle') ??
                                    'Create your account, keep your taste profile with you on all devices.')
                              : (AppLocalizations.of(
                                      context,
                                    )?.get('auth_login_subtitle') ??
                                    'Sign in to your account, continue from where you left off.'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 28),

                        if (_isRegister) ...[
                          TextFormField(
                            controller: _nameCtrl,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: InputDecoration(
                              labelText:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('auth_display_name') ??
                                  'Display Name',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('auth_forgot_err_name_empty') ??
                                      'Name field cannot be empty.')
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextFormField(
                          key: const ValueKey('auth_email_field'),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )?.get('auth_email_label') ??
                                'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty ||
                                !s.contains('@') ||
                                !s.contains('.')) {
                              return AppLocalizations.of(
                                    context,
                                  )?.get('auth_forgot_err_email_invalid') ??
                                  'Enter a valid email.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          key: const ValueKey('auth_password_field'),
                          controller: _passCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText:
                                AppLocalizations.of(
                                  context,
                                )?.get('auth_password_label') ??
                                'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v ?? '').length < 8
                              ? (AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_err_pass_length') ??
                                    'Password must be at least 8 characters.')
                              : null,
                        ),
                        if (!_isRegister) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const ForgotPasswordSheet(),
                                );
                              },
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.get('auth_forgot_password_link') ??
                                    'Forgot Password?',
                              ),
                            ),
                          ),
                        ],

                        if (auth.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)?.get(auth.error!) ??
                                auth.error!,
                            style: TextStyle(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 24),
                        FilledButton(
                          key: const ValueKey('auth_login_button'),
                          onPressed: auth.loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: auth.loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(
                                  _isRegister
                                      ? (AppLocalizations.of(
                                              context,
                                            )?.get('auth_button_register') ??
                                            'Register')
                                      : (AppLocalizations.of(
                                              context,
                                            )?.get('auth_button_login') ??
                                            'Login'),
                                ),
                        ),
                        if (AppConfig.googleSignInConfigured) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.get('auth_or') ??
                                      'veya',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: auth.loading ? null : _googleSignIn,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: auth.loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    child: const Text(
                                      'G',
                                      style: TextStyle(
                                        color: Color(0xFF4285F4),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                            label: Text(
                              auth.loading
                                  ? (AppLocalizations.of(
                                          context,
                                        )?.get('auth_signing_in') ??
                                        'Giriş yapılıyor...')
                                  : (AppLocalizations.of(
                                          context,
                                        )?.get('auth_google_button') ??
                                        'Google ile devam et'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: auth.loading
                              ? null
                              : () =>
                                    setState(() => _isRegister = !_isRegister),
                          child: Text(
                            _isRegister
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('auth_toggle_to_login') ??
                                      'Already have an account? Sign In')
                                : (AppLocalizations.of(
                                        context,
                                      )?.get('auth_toggle_to_register') ??
                                      "Don't have an account? Sign Up"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AuthLoadingOverlay(visible: auth.loading),
      ],
    );
  }
}
