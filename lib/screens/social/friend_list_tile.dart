import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'friend_activity_screen.dart';

/// Arkadaş listesi satırı: avatar, ad/kullanıcı adı, zevk uyumu rozeti ve
/// çıkarma butonu (onaylı). Dokununca arkadaşın aktivite ekranı açılır.
class FriendListTile extends StatelessWidget {
  final Friend friend;
  final int? tasteScore;
  final Future<void> Function() onRemove;

  const FriendListTile({
    super.key,
    required this.friend,
    required this.tasteScore,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = friend.displayName ?? friend.username;
    final handle = friend.username;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FriendActivityScreen(
              friendId: friend.id,
              friendName: name,
              friendUsername: handle,
              tasteScore: tasteScore,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: CinemaGradients.crimson,
              ),
              alignment: Alignment.center,
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (handle.isNotEmpty)
                    Text(
                      '@$handle',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  if (tasteScore != null) ...[
                    const SizedBox(height: 6),
                    // Zevk uyumu rozeti (0-100)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.gold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            color: c.gold,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.of(context)
                                    ?.get('taste_score_match')
                                    .replaceAll('{}', '$tasteScore') ??
                                '$tasteScore% match',
                            style: TextStyle(
                              color: c.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.person_remove_rounded,
                color: c.red.withValues(alpha: 0.7),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text(
                      AppLocalizations.of(context)?.get('remove_friend') ??
                          'Remove Friend',
                    ),
                    content: Text(
                      AppLocalizations.of(context)
                              ?.get('remove_friend_confirm_msg')
                              .replaceAll('{}', name) ??
                          'Are you sure you want to remove $name from friends?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          AppLocalizations.of(context)?.get('profile_cancel') ??
                              'Cancel',
                          style: TextStyle(color: c.dim),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await onRemove();
                        },
                        child: Text(
                          AppLocalizations.of(context)?.get('remove') ??
                              'Remove',
                          style: TextStyle(color: c.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
