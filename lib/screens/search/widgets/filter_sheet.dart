import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../results_screen.dart';
import 'filter_chip.dart';
import 'filter_labels.dart';

/// Arama gelişmiş filtre alt sayfası.
class SearchFilterSheet {
  static void show(
    BuildContext context, {
    required String? selectedLanguage,
    required int? selectedProvider,
    required double? selectedMinRating,
    required void Function(String? language, int? provider, double? minRating)
    onApply,
  }) {
    HapticFeedback.lightImpact();
    String? localLang = selectedLanguage;
    int? localProv = selectedProvider;
    double? localRating = selectedMinRating;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final c = ctx.c;
          final media = MediaQuery.of(ctx);
          final hasActive =
              localLang != null || localProv != null || localRating != null;

          String t(String key, String fallback) =>
              AppLocalizations.of(ctx)?.get(key) ?? fallback;

          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: media.size.height * 0.9,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    10 + media.viewPadding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: c.bg.withValues(alpha: c.isLight ? 0.96 : 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              t('advanced_filters', 'Advanced Filters'),
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            if (hasActive)
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    localLang = null;
                                    localProv = null;
                                    localRating = null;
                                  });
                                },
                                child: Text(
                                  t('search_clear', 'Temizle'),
                                  style: TextStyle(
                                    color: c.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SectionLabel(t('country_region', 'COUNTRY / REGION')),
                        const SizedBox(height: 10),
                        _RegionGrid(
                          selected: localLang,
                          onSelect: (value) =>
                              setModalState(() => localLang = value),
                        ),
                        const SizedBox(height: 22),
                        _SectionLabel(t('platform', 'PLATFORM')),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SearchFilterChip(
                              label: t('lang_all', 'All'),
                              selected: localProv == null,
                              onTap: () =>
                                  setModalState(() => localProv = null),
                            ),
                            ...SearchFilterLabels.providers.entries.map(
                              (entry) => SearchFilterChip(
                                label: entry.value,
                                selected: localProv == entry.key,
                                onTap: () =>
                                    setModalState(() => localProv = entry.key),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SectionLabel(
                          t('minimum_tmdb_score', 'MINIMUM TMDB SCORE'),
                        ),
                        const SizedBox(height: 10),
                        _ScoreRail(
                          selected: localRating,
                          onSelect: (value) =>
                              setModalState(() => localRating = value),
                        ),
                        const SizedBox(height: 28),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            onApply(localLang, localProv, localRating);
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ResultsScreen(
                                  originalLanguage: localLang,
                                  providerId: localProv,
                                  minRating: localRating,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: CinemaGradients.crimson,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              t('filter_and_list', 'Filter and List'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text(
      text,
      style: TextStyle(
        color: c.dim,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// Bölge seçimi: kısa etiket + ikon, 2 sütun ızgara — uzun chip yığını yerine.
class _RegionGrid extends StatelessWidget {
  const _RegionGrid({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final allLabel = AppLocalizations.of(context)?.get('lang_all') ?? 'All';

    final tiles = <Widget>[
      _RegionTile(
        icon: Icons.travel_explore_rounded,
        label: allLabel,
        semanticsLabel: allLabel,
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      ...SearchFilterLabels.languageOrder.map((key) {
        final short = SearchFilterLabels.languageShort(context, key);
        final full = SearchFilterLabels.languageLabel(context, key);
        return _RegionTile(
          icon: SearchFilterLabels.languageIcon(key),
          label: short,
          semanticsLabel: full,
          selected: selected == key,
          onTap: () => onSelect(key),
        );
      }),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: semanticsLabel,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? c.red.withValues(alpha: c.isLight ? 0.10 : 0.14)
                  : c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? c.red : c.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? c.red : c.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? c.ink : c.dim,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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

/// Puan eşiği: tek satırlık segment rayı (ordinal seçim).
class _ScoreRail extends StatelessWidget {
  const _ScoreRail({required this.selected, required this.onSelect});

  final double? selected;
  final ValueChanged<double?> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final allLabel = AppLocalizations.of(context)?.get('lang_all') ?? 'All';
    final options = <MapEntry<double?, String>>[
      MapEntry(null, allLabel),
      ...SearchFilterLabels.ratings.entries,
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: _ScoreSegment(
                label: options[i].value,
                selected: selected == options[i].key,
                onTap: () => onSelect(options[i].key),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreSegment extends StatelessWidget {
  const _ScoreSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.red : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : c.dim,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
