import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'results_language.dart';

class ResultsActiveFilterBar extends StatelessWidget {
  final String? filterLanguage;
  final RangeValues yearRange;
  final int currentYear;
  final VoidCallback onClearLanguage;
  final VoidCallback onClearYear;

  const ResultsActiveFilterBar({
    super.key,
    required this.filterLanguage,
    required this.yearRange,
    required this.currentYear,
    required this.onClearLanguage,
    required this.onClearYear,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final localeCode = Localizations.localeOf(context).languageCode;
    final language = filterLanguage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (language != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RawChip(
                  label: Text(
                    resultsLanguageLabel(
                      language,
                      resultsLanguageFallbackLabel(language),
                      localeCode,
                    ),
                    style: TextStyle(color: c.ink, fontSize: 12),
                  ),
                  backgroundColor: c.red.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onDeleted: onClearLanguage,
                  deleteIconColor: c.dim,
                ),
              ),
            if (resultsIsYearRangeActive(yearRange, currentYear))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RawChip(
                  label: Text(
                    '${yearRange.start.round()} - ${yearRange.end.round()}',
                    style: TextStyle(color: c.ink, fontSize: 12),
                  ),
                  backgroundColor: c.red.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onDeleted: onClearYear,
                  deleteIconColor: c.dim,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
