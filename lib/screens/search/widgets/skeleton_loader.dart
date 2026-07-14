import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/pulsing_placeholder.dart';

/// Arama sonuçları yüklenirken gösterilen iskelet liste.
class SearchSkeletonLoader extends StatelessWidget {
  const SearchSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (ctx, i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const SizedBox(
                  width: 44,
                  height: 64,
                  child: PulsingPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 30,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.dim, size: 20),
            ],
          ),
        );
      },
    );
  }
}
