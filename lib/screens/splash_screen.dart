import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

/// Markalı, sinematik açılış ekranı.
/// Karanlıktan bir ışık doğar, "cinema+" wordmark'ı zarifçe belirir,
/// altın bir çizgi çizilir ve ana ekrana yumuşakça geçilir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/providers.dart';
import '../services/db_helper.dart';

/// Markalı, sinematik açılış ekranı.
/// Karanlıktan bir ışık doğar, "cinema+" wordmark'ı zarifçe belirir,
/// altın bir çizgi çizilir ve ana ekrana yumuşakça geçilir.
class SplashScreen extends ConsumerStatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  // Zaman aralıkları
  late final Animation<double> _glow = _curve(0.00, 0.55, Curves.easeOut);
  late final Animation<double> _markFade = _curve(0.18, 0.62, Curves.easeOut);
  late final Animation<double> _markScale = Tween(begin: 0.86, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _intro,
          curve: const Interval(0.18, 0.70, curve: Curves.easeOutCubic),
        ),
      );
  late final Animation<double> _tracking = Tween(begin: 16.0, end: 6.0).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.18, 0.78, curve: Curves.easeOutCubic),
    ),
  );
  late final Animation<double> _line = _curve(0.52, 0.86, Curves.easeOutCubic);
  late final Animation<double> _tagline = _curve(0.66, 0.92, Curves.easeOut);

  Animation<double> _curve(double a, double b, Curve c) => CurvedAnimation(
    parent: _intro,
    curve: Interval(a, b, curve: c),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _startPrefetchAndNavigation();
  }

  Future<void> _startPrefetchAndNavigation() async {
    final tmdb = ref.read(tmdbServiceProvider);

    // Delete expired cache entries (> 31 days old) in the background to not clip 30-day items
    DatabaseHelper().deleteExpiredTmdbCache(2678400000).catchError((e) {
      debugPrint('Cache eviction failed: $e');
    });

    final page = ref.read(browsePopularPageProvider);

    // Start prefetching in parallel (trending & popular movie & popular TV)
    final prefetchFuture =
        Future.wait([
              tmdb.getTrending(),
              tmdb.getPopular(isTV: false, page: page),
              tmdb.getPopular(isTV: true, page: page),
            ])
            .then((results) {
              if (mounted && results.isNotEmpty) {
                final list = results[0];
                // Pre-cache the top 3 movie posters to GPU memory
                for (var i = 0; i < math.min(3, list.length); i++) {
                  final url = list[i].posterUrl;
                  if (url.isNotEmpty) {
                    precacheImage(CachedNetworkImageProvider(url), context);
                  }
                }
              }
            })
            .catchError((_) {
              // Ignore prefetch network errors so splash flow is not blocked
            });

    final minDurationFuture = Future.delayed(
      const Duration(milliseconds: 1800),
    );
    final maxWaitFuture = Future.delayed(const Duration(milliseconds: 2500));

    // Wait for (prefetch AND 1.8s branding animation) OR (2.5s maximum wait timeout)
    await Future.any([
      Future.wait([prefetchFuture, minDurationFuture]),
      maxWaitFuture,
    ]);

    if (!mounted) return;

    // Stop intro animation if it's still running
    _intro.stop();

    HapticFeedback.lightImpact();
    await _exit.forward();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 480),
        pageBuilder: (_, a, _) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: widget.next,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Splash system bar'ı temaya göre ayarla
    final brightness = Theme.of(context).brightness;
    SystemChrome.setSystemUIOverlayStyle(
      brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
    return Scaffold(
      backgroundColor: c.bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _exit]),
        builder: (context, _) {
          final fadeOut = 1.0 - _exit.value;
          return Opacity(
            opacity: fadeOut,
            child: CustomPaint(
              painter: _SplashGlowPainter(_glow.value, _intro.value),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Wordmark
                    Transform.scale(
                      scale: _markScale.value * (1 + 0.03 * _exit.value),
                      child: Opacity(
                        opacity: _markFade.value,
                        child: _Wordmark(tracking: _tracking.value),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Altın çizgi
                    Container(
                      width: 160 * _line.value,
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.gold,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: CinemaShadows.glow(
                          AppColors.gold,
                          strength: 0.5 * _line.value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Opacity(
                      opacity: _tagline.value,
                      child: Text(
                        AppLocalizations.of(context)?.get('tagline') ??
                            (ui.PlatformDispatcher.instance.locale.languageCode == 'tr'
                                ? 'NE İZLESEM?'
                                : 'WHAT TO WATCH?'),
                        style: TextStyle(
                          color: c.dim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final double tracking;
  const _Wordmark({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      letterSpacing: tracking,
      height: 1.0,
    );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'cinema',
            style: style.copyWith(color: c.ink),
          ),
          TextSpan(
            text: '+',
            style: style.copyWith(
              color: AppColors.gold,
              shadows: CinemaShadows.glow(AppColors.gold, strength: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Merkezi büyüyen ışık + ince film grenli soluk halka.
class _SplashGlowPainter extends CustomPainter {
  final double glow; // 0..1
  final double t; // intro progress
  _SplashGlowPainter(this.glow, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final maxR = size.shortestSide * 0.95;

    // Kırmızı-altın çekirdek glow
    final r = maxR * (0.4 + 0.6 * glow);
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.crimson.withValues(alpha: 0.32 * glow),
          AppColors.goldDeep.withValues(alpha: 0.10 * glow),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, corePaint);

    // İnce dönen ışık halkası (film şeridi hissi)
    final ringAlpha = (glow * (1 - (t - 0.7).clamp(0.0, 0.3) / 0.3)).clamp(
      0.0,
      1.0,
    );
    if (ringAlpha > 0.01) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.gold.withValues(alpha: 0.18 * ringAlpha);
      final rr = maxR * (0.34 + 0.10 * t);
      const dashes = 60;
      for (var i = 0; i < dashes; i++) {
        final a0 = (i / dashes) * math.pi * 2 + t * math.pi;
        final a1 = a0 + (math.pi * 2 / dashes) * 0.5;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: rr),
          a0,
          a1 - a0,
          false,
          ringPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SplashGlowPainter old) => old.glow != glow || old.t != t;
}
