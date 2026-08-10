import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../search/widgets/filter_labels.dart';
import 'results_language.dart';

class ResultsActiveFilterBar extends StatelessWidget {
  final String? filterLanguage;
  final RangeValues yearRange;
  final int currentYear;
  final String? filterDecade;
  final String? filterGenreStr;
  final int? filterProviderId;
  final double? filterMinRating;
  final VoidCallback onClearLanguage;
  final VoidCallback onClearYear;
  final VoidCallback onClearDecade;
  final VoidCallback onClearGenre;
  final VoidCallback onClearProvider;
  final VoidCallback onClearMinRating;

  const ResultsActiveFilterBar({
    super.key,
    required this.filterLanguage,
    required this.yearRange,
    required this.currentYear,
    this.filterDecade,
    this.filterGenreStr,
    this.filterProviderId,
    this.filterMinRating,
    required this.onClearLanguage,
    required this.onClearYear,
    required this.onClearDecade,
    required this.onClearGenre,
    required this.onClearProvider,
    required this.onClearMinRating,
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
              _chip(
                c,
                resultsLanguageLabel(
                  language,
                  resultsLanguageFallbackLabel(language),
                  localeCode,
                ),
                onClearLanguage,
              ),
            if (resultsIsYearRangeActive(yearRange, currentYear))
              _chip(
                c,
                '${yearRange.start.round()} - ${yearRange.end.round()}',
                onClearYear,
              ),
            if (filterDecade != null)
              _chip(c, _decadeLabel(filterDecade!, localeCode), onClearDecade),
            if (filterGenreStr != null && filterGenreStr!.isNotEmpty)
              _chip(c, filterGenreStr!, onClearGenre),
            if (filterProviderId != null)
              _chip(
                c,
                SearchFilterLabels.providers[filterProviderId!] ??
                    'ID $filterProviderId',
                onClearProvider,
              ),
            if (filterMinRating != null)
              _chip(
                c,
                SearchFilterLabels.ratings[filterMinRating!] ??
                    '≥ ${filterMinRating!.toStringAsFixed(1)}',
                onClearMinRating,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemePalette c, String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: RawChip(
        label: Text(label, style: TextStyle(color: c.ink, fontSize: 12)),
        backgroundColor: c.red.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onDeleted: onDeleted,
        deleteIconColor: c.dim,
      ),
    );
  }

  String _decadeLabel(String decade, String localeCode) {
    final isTr = localeCode == 'tr';
    return switch (decade) {
      '2020' => '2020s',
      '2010' => '2010s',
      '2000' => '2000s',
      '1990' => '1990s',
      'classic' => isTr ? 'Klasik' : 'Classic',
      _ => decade,
    };
  }
}
