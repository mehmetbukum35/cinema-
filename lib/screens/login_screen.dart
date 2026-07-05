import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';

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
    final ok = _isRegister
        ? await notifier.register(
            _emailCtrl.text,
            _passCtrl.text,
            displayName: _nameCtrl.text.trim(),
          )
        : await notifier.login(_emailCtrl.text, _passCtrl.text);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
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
                        validator: (val) => val == null || val.trim().isEmpty
                            ? (AppLocalizations.of(
                                    context,
                                  )?.get('auth_forgot_err_name_empty') ??
                                  'Name field cannot be empty.')
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
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
                        if (s.isEmpty || !s.contains('@') || !s.contains('.')) {
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
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 8
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('auth_forgot_err_pass_length') ??
                                'Password must be at least 8 characters.')
                          : null,
                    ),

                    if (auth.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        auth.error!,
                        style: TextStyle(color: cs.error),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
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
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: auth.loading
                          ? null
                          : () => setState(() => _isRegister = !_isRegister),
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
    );
  }
}
