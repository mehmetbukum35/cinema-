import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/movie.dart';
import '../../services/providers.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/blocking_loading_dialog.dart';
import '../movie_detail_sheet.dart';

/// Akış/öneri kartından yapım detayına geçiş: TMDB'den detayları çekip
/// MovieDetailSheet açar; beklerken tam ekran yükleme göstergesi gösterir.
Future<void> openMovieDetailById(
  BuildContext context,
  WidgetRef ref,
  int movieId,
  bool isTv,
) async {
  final service = ref.read(tmdbServiceProvider);
  final c = context.c;
  final tr = AppLocalizations.of(context);

  try {
    final details = await runWithBlockingLoadingDialog(
      context: context,
      color: c.gold,
      task: () => service.getFullDetails(movieId, isTV: isTv),
    );

    if (details == null) {
      if (context.mounted) {
        showAppToast(
          context,
          tr?.get('browse_conn_error') ??
              'İnternet bağlantınızı kontrol edip tekrar deneyin.',
          success: false,
        );
      }
      return;
    }

    if (context.mounted) {
      final movie = Movie.fromJson(details, isTV: isTv);
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => MovieDetailSheet(movie: movie, service: service),
      );
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        (tr?.get('error_occurred_msg') ?? 'Hata oluştu: {}').replaceAll(
          '{}',
          '$e',
        ),
        success: false,
      );
    }
  }
}
