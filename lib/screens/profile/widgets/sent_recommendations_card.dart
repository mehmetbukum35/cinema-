import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/social_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../sent_recommendations_screen.dart';

/// Arkadaşlara önerdiklerin: tüm gönderilen önerilerin toplu görünümü.
/// Yorumlarım kartıyla aynı stilde; dokununca tam liste ekranı açılır.
class SentRecommendationsCard extends ConsumerStatefulWidget {
  const SentRecommendationsCard({super.key});

  @override
  ConsumerState<SentRecommendationsCard> createState() =>
      _SentRecommendationsCardState();
}

class _SentRecommendationsCardState
    extends ConsumerState<SentRecommendationsCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(socialProvider.notifier).loadSentRecommendations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const SizedBox.shrink();

    final social = ref.watch(socialProvider);
    final count = social.sentRecommendations.length;
    final countLabel = '$count${social.sentRecommendationsHasMore ? '+' : ''}';

    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SentRecommendationsScreen()),
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
              child: Icon(Icons.send_rounded, color: c.gold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr?.get('sent_recommendations_title') ?? 'Önerdiklerim',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr?.get('sent_recommendations_subtitle') ??
                        'Arkadaşlarına gönderdiklerin',
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
                  countLabel,
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
