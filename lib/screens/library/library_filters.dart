import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

enum LibraryTypeFilter { all, movie, tv }

enum LibrarySort { added, rating, year, myRating }

String librarySortLabel(AppLocalizations? tr, LibrarySort s) => switch (s) {
  LibrarySort.added => tr?.get('sort_added') ?? 'Eklenme',
  LibrarySort.rating => tr?.get('sort_rating') ?? 'Puan',
  LibrarySort.year => tr?.get('sort_year') ?? 'Yıl',
  LibrarySort.myRating => tr?.get('sort_my_rating') ?? 'Puanım',
};

class LibrarySegmentedTabs extends StatelessWidget {
  final TabController tabController;
  final int watchCount;
  final int ratedCount;

  const LibrarySegmentedTabs({
    super.key,
    required this.tabController,
    required this.watchCount,
    required this.ratedCount,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 1),
        ),
        padding: const EdgeInsets.all(3),
        child: TabBar(
          controller: tabController,
          indicator: BoxDecoration(
            color: c.isLight ? c.gold.withValues(alpha: 0.15) : c.cardHi,
            borderRadius: BorderRadius.circular(9),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: c.gold,
          unselectedLabelColor: c.dim,
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            Tab(
              height: 38,
              text:
                  '${tr?.get('profile_watchlist') ?? 'İzleme Listesi'} · $watchCount',
            ),
            Tab(
              height: 38,
              text:
                  '${tr?.get('profile_history') ?? 'Değerlendirdiklerim'} · $ratedCount',
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryFilterRow extends StatelessWidget {
  final TabController tabController;
  final LibraryTypeFilter type;
  final LibrarySort sort;
  final ValueChanged<LibraryTypeFilter> onTypeChanged;
  final ValueChanged<LibrarySort> onSortChanged;

  const LibraryFilterRow({
    super.key,
    required this.tabController,
    required this.type,
    required this.sort,
    required this.onTypeChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    Widget chip(String label, LibraryTypeFilter value) {
      final on = type == value;
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTypeChanged(value);
        },
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.red.withValues(alpha: 0.15) : c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? c.red : c.border, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? c.red : c.dim,
              fontSize: 12,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final sorts = [
      LibrarySort.added,
      LibrarySort.rating,
      LibrarySort.year,
      if (tabController.index == 1) LibrarySort.myRating,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip(tr?.get('lang_all') ?? 'All', LibraryTypeFilter.all),
          chip(tr?.get('onboarding_movie') ?? 'Movie', LibraryTypeFilter.movie),
          chip(tr?.get('onboarding_tv') ?? 'TV', LibraryTypeFilter.tv),
          const Spacer(),
          PopupMenuButton<LibrarySort>(
            tooltip: tr?.get('sort_added') ?? 'Sırala',
            onSelected: (s) {
              HapticFeedback.lightImpact();
              onSortChanged(s);
            },
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (ctx) => [
              for (final s in sorts)
                PopupMenuItem(
                  value: s,
                  height: 40,
                  child: Row(
                    children: [
                      Icon(
                        sort == s
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 16,
                        color: sort == s ? c.gold : c.dim,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        librarySortLabel(tr, s),
                        style: TextStyle(
                          color: sort == s ? c.ink : c.dim,
                          fontSize: 13.5,
                          fontWeight: sort == s
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, color: c.gold, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    librarySortLabel(tr, sort),
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
