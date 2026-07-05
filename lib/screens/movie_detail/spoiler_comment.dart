import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class SpoilerComment extends StatefulWidget {
  final String comment;
  final bool isSpoiler;

  const SpoilerComment({
    super.key,
    required this.comment,
    required this.isSpoiler,
  });

  @override
  State<SpoilerComment> createState() => _SpoilerCommentState();
}

class _SpoilerCommentState extends State<SpoilerComment> {
  late bool _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = !widget.isSpoiler;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    if (widget.isSpoiler && !_reveal) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _reveal = true);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.rBerbat.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.rBerbat.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: c.rBerbat, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr?.get('review_spoiler_warning') ??
                      'Spoiler içeriyor. Görmek için dokunun.',
                  style: TextStyle(
                    color: c.rBerbat,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.borderSoft.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      width: double.infinity,
      child: Text(
        widget.comment,
        style: TextStyle(color: c.ink, fontSize: 13, height: 1.35),
      ),
    );
  }
}
