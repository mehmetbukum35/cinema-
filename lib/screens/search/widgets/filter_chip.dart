import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

/// Arama filtre alt sayfasındaki seçilebilir chip.
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.red.withValues(alpha: 0.15) : c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c.red : c.border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c.red : c.dim,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
