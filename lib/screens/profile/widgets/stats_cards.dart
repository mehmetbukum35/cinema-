import 'package:flutter/material.dart';
import '../../../services/prefs_service.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

/// Toplam puan sayısı + en sevilen türler kartı.
class StatsOverviewCard extends StatelessWidget {
  final int total;
  final List<dynamic> topGenres;
  const StatsOverviewCard({
    super.key,
    required this.total,
    required this.topGenres,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.red.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.movie_filter_rounded, color: c.red, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$total',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    tr?.get('profile_rating') ?? 'Ratings',
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (topGenres.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              tr?.get('profile_genres') ?? 'EN SEVDİĞİN TÜRLER',
              style: TextStyle(
                color: c.dim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: topGenres
                  .map(
                    (g) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(20),
                        border: c.isLight
                            ? Border.all(color: c.border, width: 1)
                            : null,
                      ),
                      child: Text(
                        PrefsService.genreName(g as int),
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Berbat/Eh/İyi/Harika dağılım çubukları.
class RatingDistributionCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const RatingDistributionCard({super.key, required this.stats});

  static const _ratingLabels = ['Awful', 'Meh', 'Good', 'Amazing'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
    final values = [
      stats['berbat'] as int? ?? 0,
      stats['eh'] as int? ?? 0,
      stats['iyi'] as int? ?? 0,
      stats['harika'] as int? ?? 0,
    ];
    final total = values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)?.get('profile_stats') ?? 'MY RATINGS',
            style: TextStyle(
              color: c.dim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(4, (i) {
            final frac = total > 0 ? values[i] / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      AppLocalizations.of(context)?.get(
                            [
                              'profile_berbat',
                              'profile_eh',
                              'profile_iyi',
                              'profile_harika',
                            ][i],
                          ) ??
                          _ratingLabels[i],
                      style: TextStyle(
                        color: ratingColors[i],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 8,
                        backgroundColor: c.isLight
                            ? c.border
                            : const Color(0xFF2A2A2A),
                        valueColor: AlwaysStoppedAnimation(ratingColors[i]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${values[i]}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
