import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../services/prefs_service.dart';
import '../../theme/app_theme.dart';
import 'onboarding_helpers.dart';

class GenreStep extends StatelessWidget {
  final int stepIndex;
  final String title;
  final String subtitle;
  final List<(int, String, IconData)> genres;
  final Set<int> selected;
  final void Function(int) onToggle;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;

  const GenreStep({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.subtitle,
    required this.genres,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildDots(context, stepIndex, onSkip: onSkip),
              const SizedBox(height: 22),
              Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: TextStyle(color: c.dim, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: genres.length,
            itemBuilder: (ctx, i) {
              final (id, _, icon) = genres[i];
              final name = PrefsService.genreName(id);
              final isSel = selected.contains(id);
              return GestureDetector(
                onTap: () => onToggle(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isSel ? c.red.withValues(alpha: 0.12) : c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSel ? c.red : c.textFaint,
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: isSel ? c.red : c.dim, size: 26),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: isSel ? c.ink : c.dim,
                          fontSize: 11.5,
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: buildContinueBtn(
            context,
            label:
                AppLocalizations.of(context)?.get('onboarding_next') ?? 'Devam',
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}
