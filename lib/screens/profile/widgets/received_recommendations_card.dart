import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/social_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../received_recommendations_screen.dart';

/// Arkadaşlardan gelen öneriler: tüm alınan önerilerin toplu görünümü.
/// Gönderilen öneriler kartıyla aynı stilde; dokununca tam liste ekranı açılır.
class ReceivedRecommendationsCard extends ConsumerStatefulWidget {
  const ReceivedRecommendationsCard({super.key});

  @override
  ConsumerState<ReceivedRecommendationsCard> createState() =>
      _ReceivedRecommendationsCardState();
}

class _ReceivedRecommendationsCardState
    extends ConsumerState<ReceivedRecommendationsCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(socialProvider.notifier).loadReceivedRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const SizedBox.shrink();

    final count = ref.watch(socialProvider).receivedRecommendations.length;

    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ReceivedRecommendationsScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.gold.withValues(alpha: 0.35), width: 1),
          boxShadow: c.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.inbox_rounded, color: c.gold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr?.get('received_recommendations_title') ??
                        'Önerilenler',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr?.get('received_recommendations_subtitle') ??
                        'Sana gelen film ve diziler',
                    style: TextStyle(color: c.dim, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.gold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Icon(Icons.chevron_right_rounded, color: c.dim),
          ],
        ),
      ),
    );
  }
}
