import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// İtalik tagline satırı (varsa hero'nun altında görünür).
class TaglineText extends StatelessWidget {
  final String tagline;

  const TaglineText({super.key, required this.tagline});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text(
      '"$tagline"',
      style: TextStyle(
        color: c.dim,
        fontSize: 13,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Konu özeti kartı.
class StorylineCard extends StatelessWidget {
  final String overview;

  const StorylineCard({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        overview,
        style: TextStyle(color: c.ink, fontSize: 14, height: 1.6),
      ),
    );
  }
}
