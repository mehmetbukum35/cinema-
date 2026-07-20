import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';
import 'rating_btn.dart';

/// Alt değerlendirme düğmeleri satırı (geri al + 4 puan + izlemedim).
class SwipeRatingButtonRow extends StatelessWidget {
  final int currentIndex;
  final VoidCallback onUndo;
  final ValueChanged<int> onRate;

  const SwipeRatingButtonRow({
    super.key,
    required this.currentIndex,
    required this.onUndo,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = constraints.maxWidth;
              final double scale = maxWidth < 340
                  ? (maxWidth / 340).clamp(0.75, 1.0)
                  : 1.0;

              final double undoSize = 44.0 * scale;
              final double berbatSize = 68.0 * scale;
              final double ehSize = 80.0 * scale;
              final double iyiSize = 80.0 * scale;
              final double harikaSize = 68.0 * scale;

              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Semantics(
                      label:
                          AppLocalizations.of(context)?.get('semantics_undo') ??
                          'Undo rating',
                      button: true,
                      enabled: currentIndex > 0,
                      child: SpringButton(
                        onTap: currentIndex > 0 ? onUndo : null,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: undoSize,
                              height: undoSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.surface,
                              ),
                              child: Icon(
                                Icons.undo_rounded,
                                color: currentIndex > 0
                                    ? (c.isLight ? c.dim : Colors.white54)
                                    : (c.isLight
                                          ? c.textFaint
                                          : Colors.white12),
                                size: 20 * scale,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SwipeRatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_berbat') ??
                          'Awful',
                      color: c.rBerbat,
                      size: berbatSize,
                      onTap: () => onRate(0),
                    ),
                    SwipeRatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_eh') ??
                          'Meh',
                      color: c.rEh,
                      size: ehSize,
                      onTap: () => onRate(1),
                    ),
                    SwipeRatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_iyi') ??
                          'Good',
                      color: c.rIyi,
                      size: iyiSize,
                      onTap: () => onRate(2),
                    ),
                    SwipeRatingBtn(
                      label:
                          AppLocalizations.of(context)?.get('profile_harika') ??
                          'Amazing',
                      color: c.rHarika,
                      size: harikaSize,
                      onTap: () => onRate(3),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SpringButton(
            onTap: () => onRate(-1),
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                AppLocalizations.of(context)?.get('onboarding_not_watched') ??
                    'Not Watched',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
