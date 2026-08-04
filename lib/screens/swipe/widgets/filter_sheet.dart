import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/swipe_provider.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import 'filter_chip.dart';
import 'filter_labels.dart';

/// Swipe içerik filtreleri alt sayfası.
class SwipeFilterSheet {
  static void show(BuildContext context, WidgetRef ref, SwipeState state) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final c = context.c;
            final activeLang = state.languageFilter;
            final activeProv = state.providerFilter;
            final activeCount =
                (activeLang != null ? 1 : 0) + (activeProv != null ? 1 : 0);

            String t(String key, String fallback) =>
                AppLocalizations.of(context)?.get(key) ?? fallback;

            void apply({String? language, int? provider}) {
              ref
                  .read(swipeProvider.notifier)
                  .updateFilters(
                    languageFilter: language,
                    providerFilter: provider,
                  );
              Navigator.pop(ctx);
            }

            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    color: (c.isLight ? c.surface : const Color(0xFF161616))
                        .withValues(alpha: c.isLight ? 0.94 : 0.85),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    32 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: c.isLight ? c.border : Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t('content_filters', 'Content Filters')}'
                                '${activeCount > 0 ? (AppLocalizations.of(context)?.get('active_count_label').replaceAll('{}', '$activeCount') ?? ' ($activeCount Active)') : ''}',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (activeLang != null || activeProv != null)
                              TextButton(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  apply(language: null, provider: null);
                                },
                                child: Text(
                                  t('search_clear', 'Temizle'),
                                  style: TextStyle(
                                    color: c.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _SectionHeader(
                          label: t('language_region', 'LANGUAGE / REGION'),
                          active: activeLang != null,
                        ),
                        const SizedBox(height: 10),
                        _RegionGrid(
                          selected: activeLang,
                          onSelect: (value) =>
                              apply(language: value, provider: activeProv),
                        ),
                        const SizedBox(height: 24),
                        _SectionHeader(
                          label: t(
                            'streaming_platforms',
                            'STREAMING PLATFORMS',
                          ),
                          active: activeProv != null,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SwipeFilterChip(
                              label: t('lang_all', 'All'),
                              selected: activeProv == null,
                              onTap: () =>
                                  apply(language: activeLang, provider: null),
                            ),
                            ...SwipeFilterLabels.providers.entries.map(
                              (entry) => SwipeFilterChip(
                                label: entry.value,
                                selected: activeProv == entry.key,
                                onTap: () => apply(
                                  language: activeLang,
                                  provider: entry.key,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.dim,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.red),
          ),
        ],
      ],
    );
  }
}

class _RegionGrid extends StatelessWidget {
  const _RegionGrid({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final allLabel = AppLocalizations.of(context)?.get('lang_all') ?? 'All';

    final tiles = <Widget>[
      _RegionTile(
        icon: SwipeFilterLabels.languageIcon(null),
        label: allLabel,
        semanticsLabel: allLabel,
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      ...SwipeFilterLabels.languageOrder.map((key) {
        final short = SwipeFilterLabels.languageShort(context, key);
        final full = SwipeFilterLabels.languageLabel(context, key);
        return _RegionTile(
          icon: SwipeFilterLabels.languageIcon(key),
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
