import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet'lerin ÜZERİNDE de görünen kısa geri bildirim.
///
/// SnackBar alttaki Scaffold'a çizildiği için, açık bir modal sheet'in
/// (ör. film detayı) içinden gösterilince modalın arkasında kalıyor ve
/// kullanıcı işlemin yapıldığını hiç göremiyordu. Bu yardımcı kök Overlay'e
/// çizer — dialog ve sheet'ler dahil her şeyin üstündedir.
void showAppToast(BuildContext context, String message, {bool success = true}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final c = context.c;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      color: success ? c.green : c.red,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  final String message;
  final Color color;
  final VoidCallback onDone;

  const _AppToast({
    required this.message,
    required this.color,
    required this.onDone,
  });

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _ac.forward();
    await Future.delayed(const Duration(milliseconds: 2400));
    if (mounted) await _ac.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 40,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _ac,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
