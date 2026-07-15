import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ResultsSkeletonCard extends StatefulWidget {
  final int delay;
  const ResultsSkeletonCard({super.key, required this.delay});

  @override
  State<ResultsSkeletonCard> createState() => _ResultsSkeletonCardState();
}

class _ResultsSkeletonCardState extends State<ResultsSkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween(
      begin: 0.4,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, child) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Color.lerp(context.c.surface, context.c.cardHi, _anim.value),
      ),
    ),
  );
}
