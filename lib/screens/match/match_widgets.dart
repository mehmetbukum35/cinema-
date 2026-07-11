import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Intro banner shown at the top of each match mode.
class MatchIntroBanner extends StatelessWidget {
  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String description;

  const MatchIntroBanner({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSoft),
        boxShadow: CinemaShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.red.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: palette.red, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: palette.dim,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sliding segmented controller for Movie / Couch / Friend modes.
class MatchModeSelector extends StatelessWidget {
  final int matchMode;
  final ValueChanged<int> onModeChanged;

  const MatchModeSelector({
    super.key,
    required this.matchMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final indicatorWidth = (width - 8) / 3;
        return Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.borderSoft),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                left: matchMode * indicatorWidth,
                top: 0,
                bottom: 0,
                width: indicatorWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: CinemaGradients.crimson,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: CinemaShadows.glow(c.red, strength: 0.3),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: MatchSegmentedTab(
                      mode: 0,
                      activeMode: matchMode,
                      icon: Icons.compare_arrows_rounded,
                      label: AppLocalizations.of(context)
                              ?.get('movie_match_alt') ??
                          'Movie Match',
                      onTap: onModeChanged,
                    ),
                  ),
                  Expanded(
                    child: MatchSegmentedTab(
                      mode: 1,
                      activeMode: matchMode,
                      icon: Icons.people_rounded,
                      label: AppLocalizations.of(context)
                              ?.get('together_couch_title') ??
                          'Couch Mode',
                      onTap: onModeChanged,
                    ),
                  ),
                  Expanded(
                    child: MatchSegmentedTab(
                      mode: 2,
                      activeMode: matchMode,
                      icon: Icons.group_add_rounded,
                      label:
                          AppLocalizations.of(context)?.get('with_friend') ??
                              'With Friend',
                      onTap: onModeChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class MatchSegmentedTab extends StatelessWidget {
  final int mode;
  final int activeMode;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  const MatchSegmentedTab({
    super.key,
    required this.mode,
    required this.activeMode,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final active = activeMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(mode);
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : c.dim, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : c.dim,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MatchLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const MatchLegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: c.dim,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
