import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Top 20 sıra rozeti: #1 altın, gerisi crimson. Hem profil rayında hem
/// düzenleme ekranında kullanılır — tek kaynak, tutarlı görünüm.
class TopRankBadge extends StatelessWidget {
  /// 1 tabanlı sıra (#1, #2, …).
  final int rank;
  final double size;

  const TopRankBadge({super.key, required this.rank, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isTop = rank == 1;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isTop ? c.gold : null,
        gradient: isTop ? null : CinemaGradients.crimson,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: CinemaShadows.glow(isTop ? c.gold : c.red, strength: 0.45),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: isTop ? const Color(0xFF2A1E08) : Colors.white,
          fontSize: size * 0.48,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
