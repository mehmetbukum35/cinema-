import 'package:flutter/material.dart';

import '../../../models/cultural_preferences.dart';
import '../../../screens/onboarding/cultural_preference_step.dart'
    show culturalOptions;
import '../../../services/cultural_preference_service.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

class CulturalPreferencesSheet extends StatefulWidget {
  const CulturalPreferencesSheet({
    super.key,
    required this.initialValue,
    required this.onSaved,
  });

  final CulturalPreferences initialValue;
  final Future<void> Function() onSaved;

  @override
  State<CulturalPreferencesSheet> createState() =>
      _CulturalPreferencesSheetState();
}

class _CulturalPreferencesSheetState extends State<CulturalPreferencesSheet> {
  late final Map<String, CulturePreferenceLevel> _levels = Map.of(
    widget.initialValue.levels,
  );
  bool _saving = false;

  String _tr(BuildContext context, String key, String fallback) =>
      AppLocalizations.of(context)?.get(key) ?? fallback;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await CulturalPreferenceService.save(_levels, source: 'explicit_edit');
      await widget.onSaved();
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _tr(
                  context,
                  'cultural_preferences_title',
                  'Sinema kültürü tercihlerin',
                ),
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _tr(
                  context,
                  'cultural_preferences_edit_desc',
                  'Önerilerinde hangi sinemaları daha sık görmek istediğini seç.',
                ),
                style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: culturalOptions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final (key, icon) = culturalOptions[index];
                  final selected =
                      _levels[key] ?? CulturePreferenceLevel.neutral;
                  return Semantics(
                    container: true,
                    label: _tr(context, 'culture_$key', key),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == CulturePreferenceLevel.neutral
                              ? c.border
                              : c.red,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                icon,
                                color:
                                    selected == CulturePreferenceLevel.neutral
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
                          SegmentedButton<CulturePreferenceLevel>(
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
                            onSelectionChanged: _saving
                                ? null
                                : (values) => setState(() {
                                    if (values.isEmpty) {
                                      _levels.remove(key);
                                    } else {
                                      _levels[key] = values.first;
                                    }
                                  }),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: c.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _tr(context, 'profile_save', 'Kaydet'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
