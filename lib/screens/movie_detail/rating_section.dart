import 'package:flutter/material.dart';

import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spring_button.dart';
import 'detail_section_label.dart';

/// Berbat/Eh/İyi/Harika puan butonları sırası. Sunumsal: dokunuşun ne
/// yapacağı (kaydet/sil/onay/telemetri) orkestratördeki [onTap]'e aittir.
class RatingSection extends StatelessWidget {
  final int? currentRating;
  final Future<void> Function(int rating) onTap;

  const RatingSection({
    super.key,
    required this.currentRating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final labels = [
      tr?.get('recap_stat_awful') ?? 'Awful',
      tr?.get('recap_stat_meh') ?? 'Meh',
      tr?.get('recap_stat_good') ?? 'Good',
      tr?.get('recap_stat_amazing') ?? 'Amazing',
    ];
    final colors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionLabel('detail_rate_title'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var rating = 0; rating < 4; rating++) ...[
              if (rating > 0) const SizedBox(width: 6),
              Expanded(
                child: _RatingButton(
                  rating: rating,
                  color: colors[rating],
                  label: labels[rating],
                  active: currentRating == rating,
                  onTap: () => onTap(rating),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  final int rating;
  final Color color;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RatingButton({
    required this.rating,
    required this.color,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final semanticsKey = switch (rating) {
      0 => 'semantics_rate_awful',
      1 => 'semantics_rate_meh',
      2 => 'semantics_rate_good',
      3 => 'semantics_rate_amazing',
      _ => 'semantics_rate_good',
    };
    final semanticsLabel = active
        ? (tr?.get('semantics_rate_undo').replaceAll('{}', label) ??
              'Remove $label rating')
        : (tr?.get(semanticsKey) ?? label);

    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        selected: active,
        child: SpringButton(
          onTap: onTap,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: active ? color : c.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? color : c.borderSoft,
                width: active ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppColors.onRatingFill(color) : c.dim,
                fontSize: 12,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
