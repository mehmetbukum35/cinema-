import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'spoiler_comment.dart';

/// Arkadaş/topluluk yorum kartı. [onReport] ve [onBlock] verilirse sağ üstte
/// moderasyon menüsü (şikayet et / kullanıcıyı engelle) gösterilir; ikisi de
/// null ise (ör. misafir kullanıcı) menü hiç çizilmez.
class ReviewItem extends StatelessWidget {
  final dynamic rev;
  final Future<void> Function(String reason)? onReport;
  final Future<void> Function()? onBlock;

  const ReviewItem({super.key, required this.rev, this.onReport, this.onBlock});

  static const _reportReasons = [
    ('profanity', 'review_report_profanity', 'Küfür / nefret söylemi'),
    ('spam', 'review_report_spam', 'Spam / reklam'),
    ('spoiler', 'review_report_spoiler', 'İşaretlenmemiş spoiler'),
    ('harassment', 'review_report_harassment', 'Taciz'),
    ('other', 'review_report_other', 'Diğer'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final int? ratingVal = rev['rating'] is int
        ? rev['rating'] as int
        : int.tryParse(rev['rating']?.toString() ?? '');
    final String reviewerName =
        (rev['friend_name'] ?? rev['friend_username'] ?? 'User').toString();
    final comment = rev['comment'] as String? ?? '';
    final isSpoiler = (rev['is_spoiler'] ?? 0) == 1;
    final hasMenu = onReport != null || onBlock != null;

    // Geçersiz/eksik puanı yanlış etiketlemektense rozet hiç gösterilmez.
    Color? badgeColor;
    String badgeText = '';
    switch (ratingVal) {
      case 3:
        badgeColor = c.rHarika;
        badgeText = tr?.get('profile_harika') ?? 'Amazing';
      case 2:
        badgeColor = c.rIyi;
        badgeText = tr?.get('profile_iyi') ?? 'Good';
      case 1:
        badgeColor = c.rEh;
        badgeText = tr?.get('profile_eh') ?? 'Meh';
      case 0:
        badgeColor = c.rBerbat;
        badgeText = tr?.get('profile_berbat') ?? 'Awful';
    }

    // Moderasyon menüsü karta uzun basmayla açılır: ufak bir ikonu nişanlamak
    // yerine hedef kartın tamamıdır. Kısa dokunuş spoiler açmada kalır,
    // gesture arena ikisini çakışmadan ayırır.
    return GestureDetector(
      onLongPress: hasMenu
          ? () {
              HapticFeedback.mediumImpact();
              _showModerationMenu(context);
            }
          : null,
      child: Container(
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
                Expanded(
                  child: Row(
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
                      Flexible(
                        child: Text(
                          reviewerName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeColor != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: badgeColor,
                              size: 10,
                            ),
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
              ],
            ),
            const SizedBox(height: 10),
            SpoilerComment(comment: comment, isSpoiler: isSpoiler),
          ],
        ),
      ),
    );
  }

  void _showModerationMenu(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final reviewerName = rev['friend_name'] ?? rev['friend_username'] ?? 'User';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                '$reviewerName',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (onReport != null)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: c.rBerbat, size: 20),
                title: Text(
                  tr?.get('review_report') ?? 'Yorumu şikayet et',
                  style: TextStyle(color: c.ink, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showReportReasons(context);
                },
              ),
            if (onBlock != null)
              ListTile(
                leading: Icon(Icons.block_rounded, color: c.rBerbat, size: 20),
                title: Text(
                  tr?.get('review_block_user') ?? 'Kullanıcıyı engelle',
                  style: TextStyle(color: c.ink, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmBlock(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showReportReasons(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                tr?.get('review_report_title') ??
                    'Bu yorumu neden şikayet ediyorsun?',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ..._reportReasons.map(
              (r) => ListTile(
                dense: true,
                title: Text(
                  tr?.get(r.$2) ?? r.$3,
                  style: TextStyle(color: c.ink, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onReport?.call(r.$1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBlock(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(
          tr?.get('review_block_confirm_title') ??
              'Bu kullanıcı engellensin mi?',
          style: TextStyle(color: c.ink, fontSize: 16),
        ),
        content: Text(
          tr?.get('review_block_confirm_msg') ??
              'Yorumlarını ve aktivitesini artık görmezsin; varsa arkadaşlık da kaldırılır.',
          style: TextStyle(color: c.dim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              tr?.get('profile_cancel') ?? 'İptal',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onBlock?.call();
            },
            child: Text(
              tr?.get('block') ?? 'Engelle',
              style: TextStyle(color: c.rBerbat, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
