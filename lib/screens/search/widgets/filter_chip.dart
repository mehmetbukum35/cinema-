import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

/// Arama filtre alt sayfasındaki seçilebilir chip.
///
/// Wrap içinde shrink-wrap olur; [Center] kullanılmaz — loose max-width
/// altında Center satırı doldurur ve chip'ler alt alta dizilir.
class SearchFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SearchFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      key: ValueKey('search_filter_semantics_$label'),
      label: label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('search_filter_touch_target_$label'),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: IntrinsicWidth(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? c.red.withValues(alpha: 0.16) : c.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? c.red : c.border,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? c.red : c.dim,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
