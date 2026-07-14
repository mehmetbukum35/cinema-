import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movie.dart';
import '../../providers/auth_provider.dart';
import '../../providers/social_provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../services/localization_service.dart';
import '../../services/prefs_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'recommend_sheet.dart';

/// Detay ekranının ekran-bağımsız akışları: arkadaşa öneri, yapımı gizleme ve
/// puan silme onayı. MovieDetailSheet dışından da (browse/swipe/search
/// kartları) çağrılırlar; oradaki statik metodlar buraya delege eder.

/// "Arkadaşına Öner" akışı: arkadaş seçici alt sayfa açar, seçilince
/// öneriyi backend'e gönderir (arkadaş push bildirimi alır).
Future<void> showRecommendSheetFor({
  required BuildContext context,
  required WidgetRef ref,
  required Movie movie,
}) async {
  final tr = AppLocalizations.of(context);
  final auth = ref.read(authProvider);
  if (!auth.isLoggedIn) {
    showAppToast(
      context,
      tr?.get('recommend_need_login') ??
          'Öneri göndermek için giriş yapmalısın.',
      success: false,
    );
    return;
  }

  // Arkadaş listesi henüz yüklenmediyse çek.
  if (ref.read(socialProvider).friends.isEmpty) {
    await ref.read(socialProvider.notifier).loadFriends();
  }
  if (!context.mounted) return;

  final friends = ref.read(socialProvider).friends;
  if (friends.isEmpty) {
    showAppToast(
      context,
      tr?.get('recommend_no_friends') ??
          'Önce Sosyal sekmesinden arkadaş eklemelisin.',
      success: false,
    );
    return;
  }

  final c = context.c;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => RecommendSheet(
      movie: movie,
      friends: friends,
      ref: ref,
      parentContext: context,
    ),
  );
}

/// Yapımı kalıcı gizleme onayı; onaylanırsa engeller, listeleri tazeler ve
/// [onBlocked] çağrılır.
void confirmBlockMovieDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Movie movie,
  required VoidCallback onBlocked,
}) {
  final c = context.c;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        AppLocalizations.of(context)?.get('hide_title') ?? 'Hide Title',
        style: TextStyle(
          color: c.ink,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        AppLocalizations.of(context)?.get('are_you_sure_you_want_to_block') ??
            'Are you sure you want to block this title and permanently hide it from all lists?',
        style: TextStyle(color: c.dim, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            AppLocalizations.of(context)?.get('profile_cancel') ?? 'Cancel',
            style: TextStyle(color: c.dim),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx); // Close dialog

            await PrefsService.blockMovie(movie.id, movie.isTV);

            if (context.mounted) {
              showAppToast(
                context,
                AppLocalizations.of(
                      context,
                    )?.get('title_hidden_and_removed_from_') ??
                    'Title hidden and removed from lists.',
              );
            }

            ref.invalidate(watchlistProvider);
            ref.invalidate(statsProvider);
            onBlocked();
          },
          child: Text(
            AppLocalizations.of(context)?.get('hide') ?? 'Hide',
            style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

/// Yorumlu bir puanı kaldırmadan önce onay ister (yorum da silinecektir).
Future<bool> confirmRatingDelete(BuildContext context) async {
  final c = context.c;
  final tr = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: c.card,
      title: Text(
        tr?.get('rating_delete_with_comment_title') ?? 'Puan kaldırılsın mı?',
        style: TextStyle(color: c.ink, fontSize: 16),
      ),
      content: Text(
        tr?.get('rating_delete_with_comment_msg') ??
            'Puanı kaldırırsan yazdığın yorum da silinir.',
        style: TextStyle(color: c.dim, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text(
            tr?.get('profile_cancel') ?? 'İptal',
            style: TextStyle(color: c.dim),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(
            tr?.get('remove') ?? 'Kaldır',
            style: TextStyle(color: c.rBerbat, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return result == true;
}
