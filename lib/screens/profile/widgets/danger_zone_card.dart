import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

/// Tehlike Bölgesi — iki yıkıcı işlem tek çerçevede, açık başlıkla.
/// Onay diyalogları yanlış dokunuşu zaten engelliyor; buradaki iş
/// gruplama ve görünürlük.
class DangerZoneCard extends StatelessWidget {
  final bool isLoggedIn;
  final VoidCallback onReset;
  final VoidCallback onDeleteAccount;

  const DangerZoneCard({
    super.key,
    required this.isLoggedIn,
    required this.onReset,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.red.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: c.red,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                (tr?.get('danger_zone') ?? 'Tehlike Bölgesi').toUpperCase(),
                style: TextStyle(
                  color: c.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DangerButton(
            icon: Icons.restart_alt_rounded,
            label: tr?.get('profile_reset_title') ?? 'Tüm Verileri Sıfırla',
            onTap: onReset,
          ),
          // Google Play politikası: hesap oluşturulabilen
          // uygulamalarda kalıcı hesap silme yolu zorunlu.
          if (isLoggedIn) ...[
            const SizedBox(height: 8),
            _DangerButton(
              icon: Icons.delete_forever_rounded,
              label: tr?.get('auth_delete_account') ?? 'Hesabı Sil',
              onTap: onDeleteAccount,
            ),
          ],
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DangerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.red.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c.red, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: c.red,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
