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

            return ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
                          Builder(
                            builder: (context) {
                              final activeCount =
                                  (activeLang != null ? 1 : 0) +
                                  (activeProv != null ? 1 : 0);
                              final filterTitle =
                                  AppLocalizations.of(
                                    context,
                                  )?.get('content_filters') ??
                                  'Content Filters';
                              final activeText = activeCount > 0
                                  ? (AppLocalizations.of(context)
                                            ?.get('active_count_label')
                                            .replaceAll('{}', '$activeCount') ??
                                        ' ($activeCount Active)')
                                  : '';
                              return Text(
                                '$filterTitle$activeText',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                          const Spacer(),
                          if (activeLang != null || activeProv != null)
                            TextButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: null,
                                      providerFilter: null,
                                    );
                                Navigator.pop(ctx);
                              },
                              child: Text(
                                AppLocalizations.of(ctx)?.get('search_clear') ??
                                    'Temizle',
                                style: TextStyle(
                                  color: c.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              return Text(
                                AppLocalizations.of(
                                      context,
                                    )?.get('language_region') ??
                                    'LANGUAGE / REGION',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                          if (activeLang != null) ...[
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Builder(
                            builder: (context) {
                              return SwipeFilterChip(
                                label:
                                    '🌐 ${AppLocalizations.of(context)?.get('lang_all') ?? (AppLocalizations.of(context)?.get('lang_all') ?? 'All')}',
                                selected: activeLang == null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(swipeProvider.notifier)
                                      .updateFilters(
                                        languageFilter: null,
                                        providerFilter: activeProv,
                                      );
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                          ...SwipeFilterLabels.languages(context).entries.map((
                            entry,
                          ) {
                            return SwipeFilterChip(
                              label: SwipeFilterLabels.languageLabel(
                                context,
                                entry.key,
                              ),
                              selected: activeLang == entry.key,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: entry.key,
                                      providerFilter: activeProv,
                                    );
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Builder(
                            builder: (context) {
                              return Text(
                                AppLocalizations.of(
                                      context,
                                    )?.get('streaming_platforms') ??
                                    'STREAMING PLATFORMS',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                          if (activeProv != null) ...[
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Builder(
                            builder: (context) {
                              return SwipeFilterChip(
                                label:
                                    AppLocalizations.of(context)?.get('all') ??
                                    '🎬 All',
                                selected: activeProv == null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  ref
                                      .read(swipeProvider.notifier)
                                      .updateFilters(
                                        languageFilter: activeLang,
                                        providerFilter: null,
                                      );
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                          ...SwipeFilterLabels.providers.entries.map((entry) {
                            return SwipeFilterChip(
                              label: entry.value,
                              selected: activeProv == entry.key,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(swipeProvider.notifier)
                                    .updateFilters(
                                      languageFilter: activeLang,
                                      providerFilter: entry.key,
                                    );
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                        ],
                      ),
                    ],
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
