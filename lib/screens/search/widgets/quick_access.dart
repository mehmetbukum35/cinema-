import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';
import '../../match_screen.dart';
import '../../results_screen.dart';
import 'quick_tile.dart';

/// Arama kutusu boşken gösterilen hızlı erişim ve geçmiş görünümü.
class SearchQuickAccess extends StatelessWidget {
  final List<String> history;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onSearchFromHistory;

  const SearchQuickAccess({
    super.key,
    required this.history,
    required this.onClearHistory,
    required this.onSearchFromHistory,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const MatchScreen(initialMode: 0, hideModeSelector: true),
                ),
              );
            },
            child: Semantics(
              button: true,
              label: tr?.get('together_similar_title') ?? 'Find Similar',
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: c.gold.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: CinemaShadows.card,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.gold.withValues(alpha: 0.14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        color: c.gold,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr?.get('together_similar_title') ?? 'Find Similar',
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tr?.get('together_similar_desc') ??
                                'Discover titles similar to one you love',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.dim,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.dim, size: 24),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (history.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  AppLocalizations.of(context)?.get('search_history') ??
                      'Son Aramalar',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClearHistory,
                  child: Semantics(
                    button: true,
                    label:
                        AppLocalizations.of(context)?.get('search_clear') ??
                        'Clear',
                    child: Text(
                      AppLocalizations.of(context)?.get('search_clear') ??
                          'Clear',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...history.map(
              (q) => GestureDetector(
                onTap: () => onSearchFromHistory(q),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: c.dim, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          q,
                          style: TextStyle(color: c.ink, fontSize: 14),
                        ),
                      ),
                      Icon(Icons.north_west_rounded, color: c.dim, size: 14),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            AppLocalizations.of(context)?.get('search_quick_search') ?? '',
            style: TextStyle(
              color: c.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SearchQuickTile(
            icon: Icons.local_fire_department_rounded,
            color: c.red,
            label:
                AppLocalizations.of(context)?.get('search_trending_movies') ??
                '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ResultsScreen(includeTv: false, isTrending: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SearchQuickTile(
            icon: Icons.tv_rounded,
            color: c.blue,
            label:
                AppLocalizations.of(context)?.get('search_trending_shows') ??
                '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ResultsScreen(includeMovies: false, isTrending: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SearchQuickTile(
            icon: Icons.star_rounded,
            color: c.gold,
            label: AppLocalizations.of(context)?.get('browse_top_rated') ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ResultsScreen(
                  minRating: 8.0,
                  sortBy: 'vote_average.desc',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SearchQuickTile(
            icon: Icons.new_releases_rounded,
            color: Colors.green,
            label:
                AppLocalizations.of(context)?.get('search_new_releases') ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ResultsScreen(
                  sortBy: 'primary_release_date.desc',
                  includeTv: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
