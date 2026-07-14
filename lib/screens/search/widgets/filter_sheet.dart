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
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(20),
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
                        Builder(
                          builder: (context) {
                            return Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('advanced_filters') ??
                                  'Advanced Filters',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        if (localLang != null ||
                            localProv != null ||
                            localRating != null)
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                localLang = null;
                                localProv = null;
                                localRating = null;
                              });
                            },
                            child: Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('search_clear') ??
                                  'Temizle',
                              style: TextStyle(
                                color: c.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context)?.get('country_region') ??
                              'COUNTRY / REGION',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return SearchFilterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  (AppLocalizations.of(
                                        context,
                                      )?.get('lang_all') ??
                                      'All'),
                              selected: localLang == null,
                              onTap: () =>
                                  setModalState(() => localLang = null),
                            );
                          },
                        ),
                        ...SearchFilterLabels.languages(context).entries.map((
                          entry,
                        ) {
                          return SearchFilterChip(
                            label: SearchFilterLabels.languageLabel(
                              context,
                              entry.key,
                            ),
                            selected: localLang == entry.key,
                            onTap: () =>
                                setModalState(() => localLang = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(context)?.get('platform') ??
                              'PLATFORM',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return SearchFilterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  'All',
                              selected: localProv == null,
                              onTap: () =>
                                  setModalState(() => localProv = null),
                            );
                          },
                        ),
                        ...SearchFilterLabels.providers.entries.map((entry) {
                          return SearchFilterChip(
                            label: entry.value,
                            selected: localProv == entry.key,
                            onTap: () =>
                                setModalState(() => localProv = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        return Text(
                          AppLocalizations.of(
                                context,
                              )?.get('minimum_tmdb_score') ??
                              'MINIMUM TMDB SCORE',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Builder(
                          builder: (context) {
                            return SearchFilterChip(
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.get('lang_all') ??
                                  'All',
                              selected: localRating == null,
                              onTap: () =>
                                  setModalState(() => localRating = null),
                            );
                          },
                        ),
                        ...SearchFilterLabels.ratings.entries.map((entry) {
                          return SearchFilterChip(
                            label: entry.value,
                            selected: localRating == entry.key,
                            onTap: () =>
                                setModalState(() => localRating = entry.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 30),
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
                          gradient: const LinearGradient(
                            colors: [AppColors.red, Color(0xFFB83050)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Builder(
                          builder: (context) {
                            return Text(
                              AppLocalizations.of(
                                    context,
                                  )?.get('filter_and_list') ??
                                  'Filter and List',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
