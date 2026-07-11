import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../../widgets/wrapped_modal.dart';
import '../../taste_dna_screen.dart';

/// 5 puanın altındaki kullanıcıya DNA'nın neden kilitli olduğunu anlatır.
class DnaLockedCard extends StatelessWidget {
  final int total;
  const DnaLockedCard({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: c.cardShadow,
      ),
      child: Row(
        children: [
          const Text('🧬', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr?.locale.languageCode == 'tr'
                      ? "Sinema DNA'n Kilitli"
                      : 'Cinema DNA Locked',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tr?.locale.languageCode == 'tr'
                      ? 'Zevk kimliğini oluşturmak için en az 5 filmi oylamalısın. Şu ana kadar $total film oyladın.'
                      : 'Rate at least 5 movies to unlock your taste identity. You have rated $total movies so far.',
                  style: TextStyle(color: c.dim, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Zevk DNA'sı ekranına götüren altın/kızıl degrade banner.
class DnaBanner extends StatelessWidget {
  const DnaBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TasteDnaScreen()));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.gold.withValues(alpha: 0.9),
              c.crimson.withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: c.isLight
              ? [
                  BoxShadow(
                    color: c.gold.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: c.gold.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            const Text('🧬', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr?.get('dna_title') ?? "Sinema DNA'n",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr?.get('dna_banner_desc') ?? 'Zevkinin kimliğini keşfet.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white70,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

/// Yıllık özet (Wrapped) modalını açan pembe/turuncu degrade banner.
class WrappedBanner extends ConsumerWidget {
  final Map<String, dynamic> stats;
  const WrappedBanner({super.key, required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = AppLocalizations.of(context);
    return SpringButton(
      onTap: () {
        final username = ref.read(authProvider).user?['username'] as String?;
        showGeneralDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (ctx, anim1, anim2) {
            return WrappedModal(stats: stats, username: username);
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF2E93), Color(0xFFFF8A00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2E93).withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr?.get('your_cinema_recap') ?? 'Your Cinema Recap!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr?.get('discover_your_cinema_journey_o') ??
                        'Discover your cinema journey of the year.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white70,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
