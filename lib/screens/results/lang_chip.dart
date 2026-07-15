import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ResultsLangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const ResultsLangChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? c.red.withValues(alpha: 0.15) : c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? c.red : c.border),
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
