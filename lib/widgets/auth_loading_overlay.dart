import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

/// Tam ekran yumuşak buzlu cam (frosted glass) yükleme ekranı.
/// Oturum açma / doğrulama sırasında kullanıcıya anlık ve şık geri bildirim verir.
class AuthLoadingOverlay extends StatefulWidget {
  final bool visible;
  final String? messageKey;
  final String? message;

  const AuthLoadingOverlay({
    super.key,
    required this.visible,
    this.messageKey,
    this.message,
  });

  @override
  State<AuthLoadingOverlay> createState() => _AuthLoadingOverlayState();
}

class _AuthLoadingOverlayState extends State<AuthLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    if (widget.visible) {
      _animController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AuthLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _animController.isDismissed) {
      return const SizedBox.shrink();
    }

    final c = context.c;
    final tr = AppLocalizations.of(context);

    final resolvedMessage =
        widget.message ??
        (widget.messageKey != null ? tr?.get(widget.messageKey!) : null) ??
        tr?.get('auth_signing_in') ??
        'Giriş yapılıyor...';

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: AbsorbPointer(
          absorbing: widget.visible,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.black.withValues(alpha: 0.55)),
                ),
              ),
              Center(
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: c.gold.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  c.gold,
                                ),
                                backgroundColor: c.border,
                              ),
                            ),
                            Icon(Icons.movie_outlined, size: 20, color: c.gold),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          resolvedMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
