import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Yavaşça süzülen iki ışık huzmesi (kırmızı + altın) ve vinyet ile
/// sinematik, yaşayan bir arkaplan. Çok hafif: tek controller, tek CustomPaint.
class CinematicBackground extends StatefulWidget {
  final Widget child;
  final bool animate;

  const CinematicBackground({
    super.key,
    required this.child,
    this.animate = true,
  });

  @override
  State<CinematicBackground> createState() => _CinematicBackgroundState();
}

class _CinematicBackgroundState extends State<CinematicBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14), // yeterince yavaş ama hissedilir
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(CinematicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

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
    final shouldAnimate = widget.animate && !reduceMotion;

    if (shouldAnimate) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      if (_c.isAnimating) _c.stop();
    }

    if (reduceMotion) {
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _AuroraPainter(0.0, pal)),
            ),
          ),
          widget.child,
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) =>
                  CustomPaint(painter: _AuroraPainter(_c.value, pal)),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final ThemePalette pal;
  _AuroraPainter(this.t, this.pal);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final light = pal.isLight;
    // Taban
    canvas.drawRect(rect, Paint()..color = pal.bg);

    final tau = math.pi * 2;

    // Kırmızı huzme — üst bölgede geniş yayda dolaşır
    final c1 = Offset(
      size.width * (0.30 + 0.28 * math.sin(t * tau)),
      size.height * (0.20 + 0.10 * math.cos(t * tau * 0.7)),
    );
    // Geniş yumuşak katman
    _glow(canvas, c1, size.width * 1.1, pal.crimson, light ? 0.05 : 0.40);
    // Odağlı parlak çekirdek (koyu temada çok daha göze çarpar)
    if (!light) _glow(canvas, c1, size.width * 0.45, pal.red, 0.32);

    // Altın huzme — alt-sağda ters yönde, farklı frekansta
    final c2 = Offset(
      size.width * (0.78 - 0.24 * math.cos(t * tau * 0.8)),
      size.height * (0.82 + 0.08 * math.sin(t * tau)),
    );
    // Geniş yumuşak katman
    _glow(canvas, c2, size.width * 1.0, pal.goldDeep, light ? 0.05 : 0.38);
    // Odağlı altın çekirdek
    if (!light) _glow(canvas, c2, size.width * 0.38, pal.gold, 0.30);

    // Ember arka huzme — ortada, farklı fazda derinlik katar
    if (!light) {
      final c3 = Offset(
        size.width * (0.55 + 0.12 * math.sin(t * tau * 1.3 + 1.2)),
        size.height * (0.55 + 0.09 * math.cos(t * tau * 0.9 + 0.5)),
      );
      _glow(canvas, c3, size.width * 0.55, pal.ember, 0.24);
    }

    // Vinyet — kenarları koyulaştırarak odağı merkeze çeker
    // Koyu temada 0.48 → glow’lar merkeze ve kenarlara daha fazla sızıyor
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          pal.bg.withValues(alpha: light ? 0.60 : 0.48),
        ],
        stops: const [0.50, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  void _glow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.pal.brightness != pal.brightness;
}
