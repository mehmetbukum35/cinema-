import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import 'app_toast.dart';

/// Misafirken taşınan puan/izleme listesi özetini tek satır toast olarak
/// gösterir. Giriş ekranı ve profildeki hızlı Google/Apple girişi ortak bu
/// tek yerden çağırır — hangi anahtarın (ikisi de / yalnız puan / yalnız
/// liste) kullanılacağına burada karar verilir, iki yerde ayrı ayrı değil.
void showGuestDataMergedToast(BuildContext context, MergedGuestData merged) {
  final tr = AppLocalizations.of(context);
  final String message;
  if (merged.ratingCount > 0 && merged.watchlistCount > 0) {
    message =
        (tr?.get('auth_guest_data_merged') ??
                '{} puanın ve {} izleme listesi kaydın hesabına taşındı.')
            .replaceFirst('{}', '${merged.ratingCount}')
            .replaceFirst('{}', '${merged.watchlistCount}');
  } else if (merged.ratingCount > 0) {
    message =
        (tr?.get('auth_guest_data_merged_ratings') ??
                '{} puanın hesabına taşındı.')
            .replaceFirst('{}', '${merged.ratingCount}');
  } else {
    message =
        (tr?.get('auth_guest_data_merged_watchlist') ??
                '{} izleme listesi kaydın hesabına taşındı.')
            .replaceFirst('{}', '${merged.watchlistCount}');
  }
  showAppToast(context, message);
}
