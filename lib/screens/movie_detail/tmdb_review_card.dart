import 'package:flutter/material.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';

/// TMDB yorumu kartı (salt okunur; 300 karakterde kırpılır).
class TmdbReviewCard extends StatelessWidget {
  final Review review;
  const TmdbReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = review;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.author,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (r.rating != null) ...[
                Icon(Icons.star_rounded, color: c.gold, size: 12),
                const SizedBox(width: 3),
                Text(
                  r.rating!.toStringAsFixed(1),
                  style: TextStyle(
                    color: c.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (r.date.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(r.date, style: TextStyle(color: c.dim, fontSize: 10)),
          ],
          const SizedBox(height: 8),
          Text(
            r.content.length > 300
                ? '${r.content.substring(0, 300)}…'
                : r.content,
            style: TextStyle(
              color: c.isLight ? const Color(0xFF3A352E) : Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
