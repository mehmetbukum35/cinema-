import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet'lerin ÜZERİNDE de görünen kısa geri bildirim.
///
/// SnackBar alttaki Scaffold'a çizildiği için, açık bir modal sheet'in
/// (ör. film detayı) içinden gösterilince modalın arkasında kalıyor ve
/// iPad klavyesi alttaki mesajları örtüyordu. Bu yardımcı kök Overlay'e
/// üstten çizer — dialog, sheet ve klavyenin üstünde kalır.
void showAppToast(BuildContext context, String message, {bool success = true}) {
  showAppSnackBar(
    context,
    message,
    backgroundColor: success ? context.c.green : context.c.red,
  );
}

/// Klavye ve alt navigasyonun üstünde, tutarlı üst konumlu geri bildirim.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final c = context.c;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AppToast(
      message: message,
      color: backgroundColor ?? c.green,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              entry.remove();
              onAction();
            },
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  final String message;
  final Color color;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDone;

  const _AppToast({
    required this.message,
    required this.color,
    required this.duration,
    this.actionLabel,
    this.onAction,
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
    await Future.delayed(widget.duration);
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
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: FadeTransition(
          opacity: _ac,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic)),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null && widget.onAction != null)
                      TextButton(
                        onPressed: widget.onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          widget.actionLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
