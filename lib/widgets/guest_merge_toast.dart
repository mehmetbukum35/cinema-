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
  final r = merged.ratingCount;
  final w = merged.watchlistCount;
  final f = merged.favoriteCount;
  final String message;
  if (r > 0 && w > 0 && f > 0) {
    message =
        (tr?.get('auth_guest_data_merged_all') ??
                '{} ratings, {} watchlist items, and {} Top 20 titles moved to your account.')
            .replaceFirst('{}', '$r')
            .replaceFirst('{}', '$w')
            .replaceFirst('{}', '$f');
  } else if (r > 0 && w > 0) {
    message =
        (tr?.get('auth_guest_data_merged') ??
                '{} puanın ve {} izleme listesi kaydın hesabına taşındı.')
            .replaceFirst('{}', '$r')
            .replaceFirst('{}', '$w');
  } else if (r > 0 && f > 0) {
    message =
        (tr?.get('auth_guest_data_merged_ratings_favorites') ??
                '{} ratings and {} Top 20 titles moved to your account.')
            .replaceFirst('{}', '$r')
            .replaceFirst('{}', '$f');
  } else if (w > 0 && f > 0) {
    message =
        (tr?.get('auth_guest_data_merged_watchlist_favorites') ??
                '{} watchlist items and {} Top 20 titles moved to your account.')
            .replaceFirst('{}', '$w')
            .replaceFirst('{}', '$f');
  } else if (r > 0) {
    message =
        (tr?.get('auth_guest_data_merged_ratings') ??
                '{} puanın hesabına taşındı.')
            .replaceFirst('{}', '$r');
  } else if (w > 0) {
    message =
        (tr?.get('auth_guest_data_merged_watchlist') ??
                '{} izleme listesi kaydın hesabına taşındı.')
            .replaceFirst('{}', '$w');
  } else {
    message =
        (tr?.get('auth_guest_data_merged_favorites') ??
                '{} Top 20 titles moved to your account.')
            .replaceFirst('{}', '$f');
  }
  showAppToast(context, message);
}
