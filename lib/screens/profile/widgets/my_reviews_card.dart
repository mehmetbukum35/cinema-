import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/prefs_service.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import '../../my_reviews_screen.dart';

/// Yorumlarım: yazılan tüm yorumların toplu görünümü/yönetimi.
/// Raylar arasında kaybolmasın diye büyük ayar kartı stilinde,
/// altın vurgulu ve yorum sayısı rozetli.
class MyReviewsCard extends StatelessWidget {
  const MyReviewsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return SpringButton(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyReviewsScreen()),
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
              child: Icon(Icons.rate_review_rounded, color: c.gold, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr?.get('my_reviews_title') ?? 'Yorumlarım',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr?.get('my_reviews_subtitle') ??
                        'Yazdığın tüm yorumlar tek yerde',
                    style: TextStyle(color: c.dim, fontSize: 12),
                  ),
                ],
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: PrefsService.getCommentedRatings(),
              builder: (_, snap) {
                final count = snap.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                );
              },
            ),
            Icon(Icons.chevron_right_rounded, color: c.dim),
          ],
        ),
      ),
    );
  }
}
