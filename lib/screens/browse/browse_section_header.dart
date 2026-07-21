import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Ray başlığı: renkli dikey çizgi + (varsa) emoji rozeti + başlık.
class BrowseSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final Gradient gradient;

  const BrowseSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (badge != null) ...[
                Text(badge!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          if (subtitle case final sub?) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Text(
                sub,
                style: TextStyle(
                  color: c.textPassive,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
