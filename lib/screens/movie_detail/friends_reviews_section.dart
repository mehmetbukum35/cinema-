import 'package:flutter/material.dart';

import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'detail_section_label.dart';
import 'review_item.dart';

/// Arkadaş ve topluluk yorumları bölümü: yükleme/boş durumları, iki liste ve
/// moderasyon ipucu şeridi. Şikayet/engelleme aksiyonları orkestratörden gelir.
class FriendsReviewsSection extends StatelessWidget {
  final bool loading;
  final List<dynamic> friendsReviews;
  final List<dynamic> communityReviews;

  /// Kullanıcı bu yapımı puanladı mı? (boş durum metnini seçer)
  final bool hasUserRated;

  /// Giriş yapmış kullanıcı yorumları şikayet edebilir/engelleyebilir.
  final bool canModerate;
  final Future<void> Function(dynamic rev, String reason) onReport;
  final Future<void> Function(dynamic rev) onBlock;

  const FriendsReviewsSection({
    super.key,
    required this.loading,
    required this.friendsReviews,
    required this.communityReviews,
    required this.hasUserRated,
    required this.canModerate,
    required this.onReport,
    required this.onBlock,
  });

  Widget _reviewItem(dynamic rev) {
    final moderatable = canModerate && rev['user_id'] != null;
    return ReviewItem(
      rev: rev,
      onReport: moderatable ? (reason) => onReport(rev, reason) : null,
      onBlock: moderatable ? () => onBlock(rev) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (friendsReviews.isEmpty && communityReviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            hasUserRated
                ? (tr?.get('review_no_friends') ??
                      'Arkadaşlarından henüz yorum yok')
                : (tr?.get('review_empty_first') ?? 'İlk yorumu sen bırak'),
            style: TextStyle(
              color: c.dim,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (friendsReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          const DetailSectionLabel('review_friends_title'),
          const SizedBox(height: 10),
          ...friendsReviews.map(_reviewItem),
        ],
        if (communityReviews.isNotEmpty) ...[
          const SizedBox(height: 20),
          const DetailSectionLabel('review_community_title'),
          const SizedBox(height: 10),
          ...communityReviews.map(_reviewItem),
        ],
        // Uzun basma görünmez bir jest; altın vurgulu bilgi şeridi keşfettirir.
        if (canModerate) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.gold.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, color: c.gold, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr?.get('review_longpress_hint') ??
                        'Şikayet etmek veya engellemek için yoruma basılı tut',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
