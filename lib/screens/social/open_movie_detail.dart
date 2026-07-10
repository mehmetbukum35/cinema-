import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/movie.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
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

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) =>
        Center(child: CircularProgressIndicator(color: c.gold)),
  );

  try {
    final details = await service.getFullDetails(movieId, isTV: isTv);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yapım detayları yüklenemedi.')),
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
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }
}
