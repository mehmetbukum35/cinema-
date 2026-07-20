import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/spring_button.dart';

/// Tek bir swipe değerlendirme düğmesi (Berbat / Eh / İyi / Harika).
class SwipeRatingBtn extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const SwipeRatingBtn({
    super.key,
    required this.label,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visualSize = size;
    final touchSize = visualSize < 44.0 ? 44.0 : visualSize;

    return Semantics(
      label: (AppLocalizations.of(context)?.locale.languageCode == 'tr')
          ? '$label olarak değerlendir'
          : 'Rate as $label',
      button: true,
      child: SpringButton(
        onTap: onTap,
        child: SizedBox(
          width: touchSize,
          height: touchSize,
          child: Center(
            child: Container(
              width: visualSize,
              height: visualSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onRatingFill(color),
                  fontSize: visualSize > 72
                      ? 14
                      : 12 * (visualSize / 80.0).clamp(0.85, 1.0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
