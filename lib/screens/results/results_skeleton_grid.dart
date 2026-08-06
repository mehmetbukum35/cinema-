import 'package:flutter/material.dart';
import 'skeleton_card.dart';

class ResultsSkeletonGrid extends StatelessWidget {
  const ResultsSkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: 6,
      itemBuilder: (_, i) => ResultsSkeletonCard(delay: i * 80),
    );
  }
}
