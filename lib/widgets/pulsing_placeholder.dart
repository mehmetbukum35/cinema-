import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'shimmer.dart';

/// Poster/görsel yüklenirken gösterilen premium iskelet.
/// Eski "nabız" efekti yerine akıcı bir ışık süpürme (shimmer) kullanır.
/// Sınıf adı geriye dönük uyumluluk için korunmuştur.
class PulsingPlaceholder extends StatelessWidget {
  const PulsingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        decoration: const BoxDecoration(gradient: CinemaGradients.surfaceSheen),
        child: const Center(
          child: Icon(Icons.movie_rounded, color: Color(0xFF2C2C34), size: 44),
        ),
      ),
    );
  }
}
