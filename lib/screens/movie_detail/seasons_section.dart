import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Dizi sezonları listesi: izlendi işaretleme (toggle) satırları.
class SeasonsSection extends StatelessWidget {
  final Map<String, dynamic>? details;
  final Set<int> watchedSeasons;
  final Future<void> Function(int seasonNumber) onToggle;

  const SeasonsSection({
    super.key,
    required this.details,
    required this.watchedSeasons,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final seasons = (details?['seasons'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((s) => (s['season_number'] as int? ?? 0) > 0)
        .toList();
    if (seasons.isEmpty) return const SizedBox.shrink();
    return Column(
      children: seasons.map((s) {
        final num = s['season_number'] as int;
        final name =
            s['name'] as String? ??
            (AppLocalizations.of(context)
                    ?.get('detail_season_label')
                    .replaceAll('{}', num.toString()) ??
                'Season $num');
        final eps = s['episode_count'] as int? ?? 0;
        final year = ((s['air_date'] as String? ?? '').length >= 4)
            ? (s['air_date'] as String).substring(0, 4)
            : '';
        final watched = watchedSeasons.contains(num);
        return GestureDetector(
          onTap: () async {
            HapticFeedback.mediumImpact();
            await onToggle(num);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: watched ? AppColors.green.withValues(alpha: 0.12) : c.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: watched
                    ? AppColors.green.withValues(alpha: 0.3)
                    : c.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  watched
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: watched ? AppColors.green : c.dim,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: watched ? AppColors.green : c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final suffix =
                              AppLocalizations.of(
                                context,
                              )?.get('detail_episodes_count') ??
                              'episodes';
                          return Text(
                            '$eps $suffix${year.isNotEmpty ? " · $year" : ""}',
                            style: TextStyle(color: c.dim, fontSize: 11),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
