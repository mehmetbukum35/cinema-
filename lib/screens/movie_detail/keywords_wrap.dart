import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Anahtar kelime rozetleri (en fazla 15).
class KeywordsWrap extends StatelessWidget {
  final List<String> keywords;
  const KeywordsWrap({super.key, required this.keywords});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: keywords
          .take(15)
          .map(
            (kw) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border),
              ),
              child: Text(
                kw,
                style: TextStyle(
                  color: c.dim,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
