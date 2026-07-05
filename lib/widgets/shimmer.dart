import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Yükleme iskeletleri için akıcı bir ışık süpürme (shimmer) efekti.
/// Çocuğun (genelde gri bloklar) üzerinden soldan sağa parlama geçirir.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Duration period;
  final Color? baseColor;
  final Color? highlightColor;

  const Shimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1500),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.c;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      if (_c.isAnimating) _c.stop();
      return widget.child;
    }

    if (!_c.isAnimating) _c.repeat();

    final base = widget.baseColor ?? (pal.isLight ? pal.border : pal.surface);
    final highlight =
        widget.highlightColor ?? (pal.isLight ? pal.surface : pal.cardHi);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: const [0.30, 0.50, 0.70],
              transform: _SlideTransform(_c.value * 2 - 1),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Gradient'i yatayda kaydırarak parlama hareketini üretir.
class _SlideTransform extends GradientTransform {
  final double slide; // -1 .. 1
  const _SlideTransform(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slide, 0, 0);
  }
}
