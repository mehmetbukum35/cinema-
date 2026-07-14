import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spring_button.dart';
import 'detail_section_label.dart';

/// Yorum editörü: metin alanı, spoiler/gizli anahtarları, karakter sayacı ve
/// kaydet butonu. Sunumsal — kaydetme iş mantığı orkestratördeki [onSave]'de.
class CommentEditor extends StatelessWidget {
  final TextEditingController controller;
  final bool isSpoiler;
  final bool isPrivate;
  final bool justSaved;
  final VoidCallback onToggleSpoiler;
  final VoidCallback onTogglePrivate;
  final Future<void> Function() onSave;

  const CommentEditor({
    super.key,
    required this.controller,
    required this.isSpoiler,
    required this.isPrivate,
    required this.justSaved,
    required this.onToggleSpoiler,
    required this.onTogglePrivate,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const DetailSectionLabel('detail_your_review'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.borderSoft),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              TextField(
                controller: controller,
                maxLength: 280,
                maxLines: 3,
                style: TextStyle(color: c.ink, fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      tr?.get('review_comment_hint') ??
                      'Share your thoughts...',
                  hintStyle: TextStyle(color: c.dim, fontSize: 13),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ToggleChip(
                    semanticsLabel:
                        tr?.get('semantics_spoiler_toggle') ??
                        'Toggle spoiler flag',
                    active: isSpoiler,
                    activeColor: c.rBerbat,
                    activeIcon: Icons.warning_amber_rounded,
                    inactiveIcon: Icons.check_circle_outline_rounded,
                    label: tr?.get('review_spoiler') ?? 'Contains spoilers',
                    onTap: onToggleSpoiler,
                  ),
                  const SizedBox(width: 8),
                  _ToggleChip(
                    semanticsLabel:
                        tr?.get('semantics_private_toggle') ??
                        'Toggle private review',
                    active: isPrivate,
                    activeColor: c.gold,
                    activeIcon: Icons.lock_rounded,
                    inactiveIcon: Icons.lock_open_rounded,
                    label: tr?.get('review_private') ?? 'Private',
                    onTap: onTogglePrivate,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Sayaç yalnızca kendini yeniler; her tuş vuruşunda koca
                  // sheet'i setState ile yeniden çizmek gereksizdi.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) => Text(
                      '${value.text.length} / 280',
                      style: TextStyle(color: c.dim, fontSize: 12),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: tr?.get('semantics_save_review') ?? 'Save review',
                    child: ElevatedButton(
                      onPressed: justSaved ? null : onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: justSaved ? c.green : c.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        justSaved
                            ? (tr?.get('saved') ?? 'Saved ✔')
                            : (tr?.get('review_save') ?? 'Save'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Spoiler ve gizli anahtarlarının ortak chip görünümü.
class _ToggleChip extends StatelessWidget {
  final String semanticsLabel;
  final bool active;
  final Color activeColor;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.semanticsLabel,
    required this.active,
    required this.activeColor,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: SpringButton(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.15)
                  : c.borderSoft.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? activeColor : c.borderSoft),
            ),
            child: Row(
              children: [
                Icon(
                  active ? activeIcon : inactiveIcon,
                  size: 14,
                  color: active ? activeColor : c.dim,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? activeColor : c.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
