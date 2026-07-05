import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../providers/watchlist_provider.dart';
import '../providers/swipe_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import 'movie_detail_sheet.dart';
import 'watchlist_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'social_screen.dart';
import 'profile/sync_section.dart';
import '../providers/social_provider.dart';
import '../widgets/spring_button.dart';
import '../widgets/wrapped_modal.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _ratingLabels = ['Berbat', 'Eh', 'İyi', 'Harika'];

  void _openAccount(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    final c = context.c;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          AppLocalizations.of(context)?.get('profile_account') ?? 'Hesap',
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          auth.user?['email'] as String? ?? '',
          style: TextStyle(color: c.dim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)?.get('semantics_close') ?? 'Kapat',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            child: Text(
              AppLocalizations.of(context)?.get('auth_logout') ?? 'Çıkış Yap',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          AppLocalizations.of(context)?.get('profile_reset_title') ??
              'Tüm Verileri Sıfırla',
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('profile_reset_content') ??
              'Değerlendirmeler, izleme listesi ve tercihler silinecek. Devam?',
          style: TextStyle(color: c.dim, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Vazgeç',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)?.get('profile_reset') ?? 'Sıfırla',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (ref.read(authProvider).isLoggedIn) {
        try {
          await ref.read(apiServiceProvider).clearRemoteSyncData();
        } catch (e) {
          debugPrint("Failed to clear remote sync data: $e");
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: c.surface,
                title: Text(
                  AppLocalizations.of(context)?.get('profile_reset_failed_title') ?? 'Sıfırlama Başarısız',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                content: Text(
                  AppLocalizations.of(context)?.get('profile_reset_failed_content') ??
                      'Sunucu verileri silinemedi. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
                  style: TextStyle(color: c.dim, fontSize: 14, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      AppLocalizations.of(context)?.get('ok') ?? 'Tamam',
                      style: TextStyle(color: c.gold, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          return; // Hata durumunda local sıfırlamaya geçme
        }
      }
      await PrefsService.resetAll();
      ref.invalidate(watchlistProvider);
      ref.invalidate(statsProvider);
      ref.invalidate(swipeProvider);
    }
  }

  Future<void> _confirmDeleteRating(
    BuildContext context,
    WidgetRef ref,
    Movie movie,
  ) async {
    final c = context.c;
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          movie.title,
          style: TextStyle(
            color: c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('do_you_want_to_delete_this_rat') ?? 'Do you want to delete this rating and remove it from your history?',
          style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(ctx, false);
            },
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Vazgeç',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx, true);
            },
            child: Text(
              AppLocalizations.of(context)?.get('delete') ?? 'Delete',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await PrefsService.deleteRating(movie.id, movie.isTV);
      ref.invalidate(statsProvider);
    }
  }

  void _openDetail(BuildContext context, WidgetRef ref, Movie movie) {
    final service = ref.read(tmdbServiceProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MovieDetailSheet(movie: movie, service: service),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final watchlistState = ref.watch(watchlistProvider);
    final statsState = ref.watch(statsProvider);

    final loading = watchlistState.isLoading || statsState.isLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CinematicBackground(
        animate: true,
        child: SafeArea(
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.dim,
                    ),
                  ),
                )
              : _content(
                  context,
                  ref,
                  watchlistState.value ?? [],
                  statsState.value ?? {},
                ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    List<Movie> watchlist,
    Map<String, dynamic> stats,
  ) {
    final c = context.c;
    final total = stats['total'] as int? ?? 0;
    final topGenres = stats['topGenres'] as List<dynamic>? ?? [];

    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.surface,
      onRefresh: () async {
        await Future.wait([
          ref.read(watchlistProvider.notifier).load(),
          ref.read(statsProvider.notifier).load(),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)?.get('tab_profile') ??
                      'Profilim',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Semantics(
                  label: AppLocalizations.of(context)?.get('profile_account') ?? 'Account',
                  button: true,
                  child: IconButton(
                    icon: Icon(
                      ref.watch(authProvider).isLoggedIn
                          ? Icons.account_circle_rounded
                          : Icons.account_circle_outlined,
                      color: ref.watch(authProvider).isLoggedIn ? c.red : c.dim,
                      size: 22,
                    ),
                    onPressed: () => _openAccount(context, ref),
                    tooltip: AppLocalizations.of(context)?.get('profile_account') ?? 'Account',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
                Semantics(
                  label:
                      AppLocalizations.of(context)?.get('theme_switch') ??
                      'Temayı değiştir',
                  button: true,
                  child: IconButton(
                    icon: Icon(
                      Theme.of(context).brightness == Brightness.light
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: c.dim,
                      size: 22,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                    tooltip:
                        AppLocalizations.of(context)?.get('theme_switch') ??
                        'Temayı değiştir',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
                Semantics(
                  label:
                      AppLocalizations.of(context)?.get('browse_refresh') ??
                      'Yenile',
                  button: true,
                  child: IconButton(
                    icon: Icon(Icons.refresh_rounded, color: c.dim, size: 22),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.invalidate(watchlistProvider);
                      ref.invalidate(statsProvider);
                    },
                    tooltip:
                        AppLocalizations.of(context)?.get('browse_refresh') ??
                        'Yenile',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Wrapped Banner ──────────────────────────────────────────────────
        if (total >= 3)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SpringButton(
                onTap: () {
                  final username = ref.read(authProvider).user?['username'] as String?;
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: false,
                    barrierColor: Colors.black,
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (ctx, anim1, anim2) {
                      return WrappedModal(
                        stats: stats,
                        username: username,
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF2E93), Color(0xFFFF8A00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF2E93).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.get('your_cinema_recap') ?? 'Your Cinema Recap!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context)?.get('discover_your_cinema_journey_o') ?? 'Discover your cinema journey of the year.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Stats card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total count + top genres
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: c.isLight
                        ? Border.all(color: c.border, width: 1)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c.red.withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              Icons.movie_filter_rounded,
                              color: c.red,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$total',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.get('profile_rating') ??
                                    'Ratings',
                                style: TextStyle(
                                  color: c.dim,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (topGenres.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)?.get('profile_genres') ??
                              'EN SEVDİĞİN TÜRLER',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: topGenres
                              .map(
                                (g) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.card,
                                    borderRadius: BorderRadius.circular(20),
                                    border: c.isLight
                                        ? Border.all(color: c.border, width: 1)
                                        : null,
                                  ),
                                  child: Text(
                                    PrefsService.genreName(g as int),
                                    style: TextStyle(
                                      color: c.ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // Rating distribution
                if (total > 0) ...[
                  const SizedBox(height: 14),
                  _ratingDistribution(context, stats),
                ],
              ],
            ),
          ),
        ),
        // Social card (only if authenticated)
        if (ref.watch(authProvider).isLoggedIn)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SocialScreen(initialTab: 0),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: c.isLight ? c.border : Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                    boxShadow: CinemaShadows.card,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.gold.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.people_alt_rounded,
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
                              AppLocalizations.of(context)?.get('together_social_title') ?? 'Social & Friends',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ref.watch(authProvider).user?['username'] != null
                                  ? '@${ref.watch(authProvider).user!['username']}'
                                  : (AppLocalizations.of(context)?.get('see_taste_matches_manage_reque') ?? 'See taste matches, manage requests and activity feeds.'),
                              style: TextStyle(color: c.dim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (ctx) {
                          final pendingCount = ref.watch(socialProvider).pendingReceived.length;
                          if (pendingCount > 0) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          return Icon(Icons.arrow_forward_ios_rounded, color: c.dim, size: 14);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Rated Movies
        if (stats['ratedMovies'] != null &&
            (stats['ratedMovies'] as List).isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                AppLocalizations.of(context)?.get('profile_history') ??
                    'DEĞERLENDİRDİKLERİM',
                style: TextStyle(
                  color: c.dim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 225,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: (stats['ratedMovies'] as List).length,
                itemBuilder: (ctx, i) {
                  final item =
                      (stats['ratedMovies'] as List)[i] as Map<String, dynamic>;
                  final movie = item['movie'] as Movie;
                  final rating = item['rating'] as int;
                  return _RatedMovieCard(
                    movie: movie,
                    rating: rating,
                    onTap: () => _openDetail(context, ref, movie),
                    onDelete: () => _confirmDeleteRating(context, ref, movie),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        // Watchlist
        if (watchlist.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('profile_watchlist') ??
                        'İZLEME LİSTESİ',
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WatchlistScreen(),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.get('see_all') ?? 'See All',
                      style: TextStyle(
                        color: c.red,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 225,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: watchlist.length,
                itemBuilder: (ctx, i) => _WatchlistCard(
                  movie: watchlist[i],
                  onTap: () => _openDetail(context, ref, watchlist[i]),
                  onRemove: () {
                    ref
                        .read(watchlistProvider.notifier)
                        .remove(watchlist[i].id, watchlist[i].isTV);
                  },
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        // Sync Card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: const SyncSection(),
          ),
        ),
        // Family Mode Card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: const _FamilyModeCard(),
          ),
        ),

        // Onboarding / Taste analysis redo button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _restartOnboarding(context);
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: c.isLight
                      ? Border.all(color: c.border, width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.gold.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        Icons.insights_rounded,
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
                            AppLocalizations.of(context)?.locale.languageCode ==
                                    'tr'
                                ? 'Zevk Analizini Yeniden Başlat'
                                : 'Restart Taste Analysis',
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context)?.locale.languageCode ==
                                    'tr'
                                ? 'Film & dizi önerilerini zevkine göre ayarla'
                                : 'Tune movie & show recommendations to your taste',
                            style: TextStyle(color: c.dim, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.dim),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Reset button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: GestureDetector(
              onTap: () => _confirmReset(context, ref),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  AppLocalizations.of(context)?.get('profile_reset_title') ??
                      'Tüm Verileri Sıfırla',
                  style: TextStyle(
                    color: c.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _ratingDistribution(BuildContext context, Map<String, dynamic> stats) {
    final c = context.c;
    final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
    final values = [
      stats['berbat'] as int? ?? 0,
      stats['eh'] as int? ?? 0,
      stats['iyi'] as int? ?? 0,
      stats['harika'] as int? ?? 0,
    ];
    final total = values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)?.get('profile_stats') ??
                'DEĞERLENDİRMELERİM',
            style: TextStyle(
              color: c.dim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(4, (i) {
            final frac = total > 0 ? values[i] / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      AppLocalizations.of(context)?.get(
                            [
                              'profile_berbat',
                              'profile_eh',
                              'profile_iyi',
                              'profile_harika',
                            ][i],
                          ) ??
                          _ratingLabels[i],
                      style: TextStyle(
                        color: ratingColors[i],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 8,
                        backgroundColor: c.isLight
                            ? c.border
                            : const Color(0xFF2A2A2A),
                        valueColor: AlwaysStoppedAnimation(ratingColors[i]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${values[i]}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _restartOnboarding(BuildContext context) async {
    await PrefsService.resetOnboarding();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WatchlistCard({
    required this.movie,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 126,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    movie.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                ColoredBox(color: c.card),
                            errorWidget: (ctx, url, err) =>
                                ColoredBox(color: c.card),
                          )
                        : ColoredBox(color: c.card),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(movie.year, style: TextStyle(color: c.dim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _RatedMovieCard extends StatelessWidget {
  final Movie movie;
  final int rating;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _RatedMovieCard({
    required this.movie,
    required this.rating,
    required this.onTap,
    this.onDelete,
  });

  static const _ratingLabels = ['Berbat', 'Eh', 'İyi', 'Harika'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ratingColors = [c.rBerbat, c.rEh, c.rIyi, c.rHarika];
    final ratingColor = ratingColors[rating.clamp(0, 3)];
    final ratingLabelKey = [
      'profile_berbat',
      'profile_eh',
      'profile_iyi',
      'profile_harika',
    ][rating.clamp(0, 3)];
    final ratingLabel =
        AppLocalizations.of(context)?.get(ratingLabelKey) ??
        _ratingLabels[rating.clamp(0, 3)];

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        width: 126,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    movie.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                ColoredBox(color: c.card),
                            errorWidget: (ctx, url, err) =>
                                ColoredBox(color: c.card),
                          )
                        : ColoredBox(color: c.card),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ratingColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ratingLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (onDelete != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.65),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(movie.year, style: TextStyle(color: c.dim, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _FamilyModeCard extends StatefulWidget {
  const _FamilyModeCard();

  @override
  State<_FamilyModeCard> createState() => _FamilyModeCardState();
}

class _FamilyModeCardState extends State<_FamilyModeCard> {
  bool _familyMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFamilyMode();
  }

  Future<void> _loadFamilyMode() async {
    final val = await PrefsService.isFamilyMode();
    if (mounted) {
      setState(() {
        _familyMode = val;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFamilyMode(bool value) async {
    HapticFeedback.lightImpact();
    await PrefsService.setFamilyMode(value);
    if (mounted) {
      setState(() {
        _familyMode = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_loading) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: CinemaShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.green.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.family_restroom_rounded,
              color: c.green,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.get('profile_family_mode') ?? 'Aile Dostu Mod (PG-13)',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)?.get('filters_out_deadpool_euphoria_') ?? 'Filters out Deadpool, Euphoria, and mature R-rated content.',
                  style: TextStyle(color: c.dim, fontSize: 11.5, height: 1.25),
                ),
              ],
            ),
          ),
          Switch(
            value: _familyMode,
            activeThumbColor: c.green,
            onChanged: _toggleFamilyMode,
          ),
        ],
      ),
    );
  }
}
