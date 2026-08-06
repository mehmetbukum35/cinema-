import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'lang_chip.dart';
import 'results_language.dart';

class ResultsFilterResult {
  final RangeValues yearRange;
  final String? language;

  const ResultsFilterResult({required this.yearRange, this.language});
}

class ResultsFilterSheet extends StatefulWidget {
  final RangeValues initialYearRange;
  final String? initialLanguage;
  final int currentYear;

  const ResultsFilterSheet({
    super.key,
    required this.initialYearRange,
    required this.initialLanguage,
    required this.currentYear,
  });

  @override
  State<ResultsFilterSheet> createState() => _ResultsFilterSheetState();
}

class _ResultsFilterSheetState extends State<ResultsFilterSheet> {
  late RangeValues _tempYear;
  late String? _tempLang;

  @override
  void initState() {
    super.initState();
    _tempYear = widget.initialYearRange;
    _tempLang = widget.initialLanguage;
  }

  void _clear() {
    setState(() {
      _tempYear = RangeValues(1970, widget.currentYear.toDouble());
      _tempLang = null;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      ResultsFilterResult(yearRange: _tempYear, language: _tempLang),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) {
                final suffix =
                    (_tempLang != null ||
                        resultsIsYearRangeActive(_tempYear, widget.currentYear))
                    ? (AppLocalizations.of(context)?.get('active') ??
                          ' (Active)')
                    : '';
                return Text(
                  '${AppLocalizations.of(context)?.get('filter') ?? 'Filter'}$suffix',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    return Text(
                      '${AppLocalizations.of(context)?.get('year') ?? 'Year'}: ${_tempYear.start.round()} – ${_tempYear.end.round()}',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    );
                  },
                ),
                if (resultsIsYearRangeActive(
                  _tempYear,
                  widget.currentYear,
                )) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          RangeSlider(
            values: _tempYear,
            min: 1970,
            max: widget.currentYear.toDouble(),
            divisions: widget.currentYear - 1970,
            activeColor: c.red,
            inactiveColor: c.card,
            onChanged: (v) => setState(() => _tempYear = v),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    return Text(
                      AppLocalizations.of(context)?.get('language') ??
                          'LANGUAGE',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    );
                  },
                ),
                if (_tempLang != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Builder(
                builder: (context) {
                  return ResultsLangChip(
                    label:
                        AppLocalizations.of(context)?.get('lang_all') ?? 'All',
                    selected: _tempLang == null,
                    onTap: () => setState(() => _tempLang = null),
                  );
                },
              ),
              ...resultsLanguages.map(
                (l) => ResultsLangChip(
                  label: resultsLanguageLabel(
                    l.code,
                    l.label,
                    Localizations.localeOf(context).languageCode,
                  ),
                  selected: _tempLang == l.code,
                  onTap: () => setState(
                    () => _tempLang = _tempLang == l.code ? null : l.code,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _clear,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      AppLocalizations.of(context)?.get('search_clear') ??
                          'Clear',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _apply,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      AppLocalizations.of(context)?.locale.languageCode == 'tr'
                          ? 'Uygula'
                          : 'Apply',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
