import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'spoiler_comment.dart';

class ReviewItem extends StatelessWidget {
  final dynamic rev;

  const ReviewItem({super.key, required this.rev});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final ratingVal = rev['rating'] is int
        ? rev['rating'] as int
        : (int.tryParse(rev['rating']?.toString() ?? '') ?? 3);
    final reviewerName = rev['friend_name'] ?? rev['friend_username'] ?? 'User';
    final comment = rev['comment'] as String? ?? '';
    final isSpoiler = (rev['is_spoiler'] ?? 0) == 1;

    Color badgeColor = c.rIyi;
    String badgeText = 'İyi';
    if (ratingVal == 3) {
      badgeColor = c.rHarika;
      badgeText = tr?.get('profile_harika') ?? 'Harika';
    } else if (ratingVal == 2) {
      badgeColor = c.rIyi;
      badgeText = tr?.get('profile_iyi') ?? 'İyi';
    } else if (ratingVal == 1) {
      badgeColor = c.rEh;
      badgeText = tr?.get('profile_eh') ?? 'Eh';
    } else if (ratingVal == 0) {
      badgeColor = c.rBerbat;
      badgeText = tr?.get('profile_berbat') ?? 'Berbat';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.border,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      reviewerName.isNotEmpty
                          ? reviewerName[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    reviewerName,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: badgeColor, size: 10),
                    const SizedBox(width: 2),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SpoilerComment(comment: comment, isSpoiler: isSpoiler),
        ],
      ),
    );
  }
}
