import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spring_button.dart';

/// Sinerji Skoru rozeti: kişisel uyum + (yeterliyse) topluluk skoru + TMDB
/// puanının ağırlıklı karması. Dokununca skor dökümü diyaloğu açılır.
class SynergyBadge extends StatelessWidget {
  final Movie movie;
  final Map<String, dynamic>? communityScore;

  const SynergyBadge({
    super.key,
    required this.movie,
    required this.communityScore,
  });

  int _calculateSynergyScore() {
    final matchVal = movie.matchScore;
    final tmdbVal = (movie.voteAverage * 10).clamp(0, 100).toInt();

    if (communityScore != null && communityScore!['enough'] == true) {
      final commVal = (communityScore!['liked_percent'] as num?)?.toInt() ?? 0;
      return (matchVal * 0.4 + commVal * 0.3 + tmdbVal * 0.3).round();
    } else {
      return (matchVal * 0.6 + tmdbVal * 0.4).round();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final synergyScore = _calculateSynergyScore();

    return SpringButton(
      onTap: () => _showScoreBreakdown(context, c, synergyScore),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.green.withValues(alpha: 0.3), width: 1),
          boxShadow: CinemaShadows.glow(c.green, strength: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: c.green, size: 14),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context)
                      ?.get('synergy_score_match')
                      .replaceAll('{}', '$synergyScore') ??
                  '$synergyScore% Match',
              style: TextStyle(
                color: c.green,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline_rounded,
              color: c.green.withValues(alpha: 0.7),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }

  void _showScoreBreakdown(
    BuildContext context,
    ThemePalette c,
    int synergyScore,
  ) {
    final isTr = AppLocalizations.of(context)?.locale.languageCode == 'tr';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Center(
          child: Text(
            AppLocalizations.of(context)?.get('match_details') ??
                'Match Details',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Featured Aggregate Synergy Score
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.green.withValues(alpha: 0.1),
                border: Border.all(
                  color: c.green.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '%$synergyScore',
                    style: TextStyle(
                      color: c.green,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)?.get('match_button') ??
                        'Match',
                    style: TextStyle(
                      color: c.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildDialogRow(
              context,
              AppLocalizations.of(context)?.get('personal_taste_match') ??
                  'Personal Taste Match',
              '%${movie.matchScore}',
              movie.matchScore / 100.0,
              c.green,
            ),
            _buildDialogRow(
              context,
              AppLocalizations.of(context)?.get('tmdb_rating') ?? 'TMDB Rating',
              '${movie.voteAverage.toStringAsFixed(1)} / 10',
              movie.voteAverage / 10.0,
              c.gold,
            ),
            if (communityScore != null && communityScore!['total'] > 0)
              _buildDialogRow(
                context,
                AppLocalizations.of(context)?.get('cinema_member_score') ??
                    'cinema+ Member Score',
                communityScore!['enough'] == true
                    ? '%${communityScore!['liked_percent']}'
                    : (isTr
                          ? '${communityScore!['total']} oy'
                          : '${communityScore!['total']} votes'),
                communityScore!['enough'] == true
                    ? ((communityScore!['liked_percent'] as num?)
                                  ?.toDouble() ??
                              0.0) /
                          100.0
                    : 0.0,
                c.red,
              ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.borderSoft),
              ),
              child: Text(
                isTr
                    ? (communityScore != null &&
                              communityScore!['enough'] == true)
                          ? 'Sinerji Skoru; kişisel zevk uyumu (%40), topluluk skoru (%30) ve TMDB puanının (%30) ağırlıklı karmasıdır.'
                          : 'Sinerji Skoru; kişisel zevk uyumu (%60) ve TMDB puanının (%40) ağırlıklı karmasıdır.'
                    : (communityScore != null &&
                          communityScore!['enough'] == true)
                    ? 'Synergy Score is a weighted mix of taste match (40%), community score (30%), and TMDB rating (30%).'
                    : 'Synergy Score is a mix of taste match (60%) and TMDB rating (40%).',
                style: TextStyle(color: c.dim, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)?.get('semantics_close') ?? 'Close',
              style: TextStyle(color: c.dim, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(
    BuildContext context,
    String label,
    String value,
    double fraction,
    Color color,
  ) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
