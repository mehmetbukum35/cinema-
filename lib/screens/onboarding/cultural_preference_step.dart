import 'package:flutter/material.dart';

import '../../models/cultural_preferences.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'onboarding_helpers.dart';

const culturalOptions = [
  ('hollywood', Icons.movie_filter_rounded),
  ('turkish', Icons.theaters_rounded),
  ('korean', Icons.auto_awesome_rounded),
  ('japanese', Icons.brightness_5_rounded),
  ('indian', Icons.music_note_rounded),
  ('iranian', Icons.camera_alt_rounded),
  ('european', Icons.public_rounded),
  ('latin_american', Icons.language_rounded),
  ('east_asian', Icons.travel_explore_rounded),
];

class CulturalPreferenceStep extends StatelessWidget {
  const CulturalPreferenceStep({
    super.key,
    required this.stepIndex,
    required this.preferences,
    required this.onChanged,
    required this.onNext,
    this.onSkip,
  });

  final int stepIndex;
  final Map<String, CulturePreferenceLevel> preferences;
  final void Function(String, CulturePreferenceLevel) onChanged;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  String _tr(BuildContext context, String key, String fallback) =>
      AppLocalizations.of(context)?.get(key) ?? fallback;

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
                _tr(
                  context,
                  'onboarding_culture_title',
                  'Hangi sinemalara yakın hissediyorsun?',
                ),
                style: TextStyle(
                  color: c.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _tr(
                  context,
                  'onboarding_culture_subtitle',
                  'Birden fazla seçebilirsin. Fikrini sonra değiştirebilirsin.',
                ),
                style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: culturalOptions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final (key, icon) = culturalOptions[index];
              final selected =
                  preferences[key] ?? CulturePreferenceLevel.neutral;
              return Semantics(
                container: true,
                label: _tr(context, 'culture_$key', key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected == CulturePreferenceLevel.neutral
                          ? c.textFaint
                          : c.red.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            color: selected == CulturePreferenceLevel.neutral
                                ? c.dim
                                : c.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _tr(context, 'culture_$key', key),
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return SegmentedButton<CulturePreferenceLevel>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: CulturePreferenceLevel.prefer,
                                label: Text(
                                  _tr(context, 'culture_prefer', 'Daha çok'),
                                ),
                              ),
                              ButtonSegment(
                                value: CulturePreferenceLevel.explore,
                                label: Text(
                                  _tr(context, 'culture_explore', 'Ara sıra'),
                                ),
                              ),
                              ButtonSegment(
                                value: CulturePreferenceLevel.avoid,
                                label: Text(
                                  _tr(context, 'culture_avoid', 'Az göster'),
                                ),
                              ),
                            ],
                            selected: selected == CulturePreferenceLevel.neutral
                                ? const {}
                                : {selected},
                            emptySelectionAllowed: true,
                            onSelectionChanged: (values) => onChanged(
                              key,
                              values.isEmpty
                                  ? CulturePreferenceLevel.neutral
                                  : values.first,
                            ),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              minimumSize: WidgetStatePropertyAll(
                                Size(constraints.maxWidth / 3 - 8, 44),
                              ),
                            ),
                          );
                        },
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
            label: _tr(context, 'onboarding_next', 'Devam'),
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}
