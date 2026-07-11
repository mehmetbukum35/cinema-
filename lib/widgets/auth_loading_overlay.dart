import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// Tam ekran giriş yüklemesi — Google hesap seçicisi kapandıktan sonraki
/// idToken/API beklemesinde kullanıcıya geri bildirim verir.
class AuthLoadingOverlay extends StatelessWidget {
  final bool visible;

  const AuthLoadingOverlay({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final message =
        AppLocalizations.of(context)?.get('auth_signing_in') ?? 'Signing in...';

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium,
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
