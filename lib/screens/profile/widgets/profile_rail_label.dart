import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

/// Ray üstü etiket: "İZLEME LİSTESİ · 34" + "Tümünü Gör".
class ProfileRailLabel extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onSeeAll;

  const ProfileRailLabel({
    super.key,
    required this.label,
    required this.count,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Text(
            '${label.toUpperCase()} · $count',
            style: TextStyle(
              color: c.dim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          // Belirgin hap buton: düz metin hâli gözden kaçıyordu.
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onSeeAll();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: c.red.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('see_all') ??
                        'Tümünü Gör',
                    style: TextStyle(
                      color: c.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: c.red, size: 13),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
