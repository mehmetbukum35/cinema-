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
import 'taste_dna_screen.dart';
import 'profile/sync_section.dart';
import '../providers/social_provider.dart';
import '../widgets/spring_button.dart';
import '../widgets/wrapped_modal.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _ratingLabels = ['Berbat', 'Eh', 'İyi', 'Harika'];

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
                  AppLocalizations.of(
                        context,
                      )?.get('profile_reset_failed_title') ??
                      'Sıfırlama Başarısız',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                content: Text(
                  AppLocalizations.of(
                        context,
                      )?.get('profile_reset_failed_content') ??
                      'Sunucu verileri silinemedi. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
                  style: TextStyle(color: c.dim, fontSize: 14, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      AppLocalizations.of(context)?.get('ok') ?? 'Tamam',
                      style: TextStyle(
                        color: c.gold,
                        fontWeight: FontWeight.bold,
                      ),
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
          AppLocalizations.of(context)?.get('do_you_want_to_delete_this_rat') ??
              'Do you want to delete this rating and remove it from your history?',
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

  static int? _lastPublishedRatingCount;
  static String? _lastPublishedUserId;

  void _autoPublishDna(WidgetRef ref) {
    Future.microtask(() async {
      try {
        final dna = await ref.read(tasteDnaServiceProvider).generate();
        await ref.read(apiServiceProvider).publishTasteDna(dna.toJson());
        debugPrint("Background DNA auto-publish succeeded!");
      } catch (e) {
        debugPrint("Background DNA auto-publish failed: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final watchlistState = ref.watch(watchlistProvider);
    final statsState = ref.watch(statsProvider);

    final loading = watchlistState.isLoading || statsState.isLoading;

    if (!loading && ref.read(authProvider).isAuthenticated) {
      final total = statsState.value?['total'] as int? ?? 0;
      final userId = ref.read(authProvider).user?['id']?.toString();
      if (total >= 5 &&
          (_lastPublishedRatingCount != total ||
              _lastPublishedUserId != userId)) {
        _lastPublishedRatingCount = total;
        _lastPublishedUserId = userId;
        _autoPublishDna(ref);
      }
    }

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

  Widget _sectionHeader(BuildContext context, ThemePalette c, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: CinemaGradients.crimson,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.dim,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void _logoutConfirm(BuildContext context, WidgetRef ref) {
    final c = context.c;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          AppLocalizations.of(context)?.get('auth_logout') ?? 'Çıkış Yap',
          style: TextStyle(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)?.get('locale') == 'tr'
              ? 'Hesabınızdan çıkış yapmak istediğinize emin misiniz?'
              : 'Are you sure you want to log out of your account?',
          style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)?.get('profile_cancel') ?? 'Vazgeç',
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

  Widget _userHeaderCard(BuildContext context, WidgetRef ref, ThemePalette c) {
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth.isLoggedIn;
    final user = auth.user;

    final String displayName =
        user?['display_name'] as String? ??
        user?['username'] as String? ??
        user?['email'] as String? ??
        '';
    final String email = user?['email'] as String? ?? '';
    final String initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    final tr = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: c.isLight ? Border.all(color: c.border, width: 1) : null,
          boxShadow: c.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isLoggedIn ? CinemaGradients.gold : null,
                color: isLoggedIn
                    ? null
                    : (c.isLight ? c.borderSoft : c.border),
              ),
              alignment: Alignment.center,
              child: Text(
                isLoggedIn ? initial : '👤',
                style: TextStyle(
                  fontSize: isLoggedIn ? 20 : 18,
                  fontWeight: FontWeight.w800,
                  color: isLoggedIn ? Colors.black : c.dim,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn
                        ? displayName
                        : (tr?.get('profile_guest') ?? 'Misafir Kullanıcı'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLoggedIn
                        ? email
                        : (tr?.get('profile_not_logged_in') ??
                              'Bulut eşitleme aktif değil'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.dim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isLoggedIn)
              IconButton(
                icon: Icon(Icons.logout_rounded, color: c.red, size: 20),
                onPressed: () => _logoutConfirm(context, ref),
                tooltip: tr?.get('auth_logout') ?? 'Çıkış Yap',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
              )
            else
              ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  tr?.get('auth_title_login') ?? 'Giriş Yap',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
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
    final tr = AppLocalizations.of(context);

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
          // Header Row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Text(
                    tr?.get('tab_profile') ?? 'Profilim',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    label: tr?.get('theme_switch') ?? 'Temayı değiştir',
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
                      tooltip: tr?.get('theme_switch') ?? 'Temayı değiştir',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  Semantics(
                    label: tr?.get('browse_refresh') ?? 'Yenile',
                    button: true,
                    child: IconButton(
                      icon: Icon(Icons.refresh_rounded, color: c.dim, size: 22),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.invalidate(watchlistProvider);
                        ref.invalidate(statsProvider);
                      },
                      tooltip: tr?.get('browse_refresh') ?? 'Yenile',
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

          // 1. User Header Card
          SliverToBoxAdapter(child: _userHeaderCard(context, ref, c)),

          // 2. Taste Identity Section
          SliverToBoxAdapter(
            child: _sectionHeader(
              context,
              c,
              tr?.get('dna_title') ?? 'Zevk Kimliğin',
            ),
          ),
          if (total < 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: c.isLight
                        ? Border.all(color: c.border, width: 1)
                        : null,
                    boxShadow: c.cardShadow,
                  ),
                  child: Row(
                    children: [
                      const Text('🧬', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr?.locale.languageCode == 'tr'
                                  ? "Sinema DNA'n Kilitli"
                                  : 'Cinema DNA Locked',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tr?.locale.languageCode == 'tr'
                                  ? 'Zevk kimliğini oluşturmak için en az 5 filmi oylamalısın. Şu ana kadar $total film oyladın.'
                                  : 'Rate at least 5 movies to unlock your taste identity. You have rated $total movies so far.',
                              style: TextStyle(
                                color: c.dim,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (total >= 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SpringButton(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TasteDnaScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          c.gold.withValues(alpha: 0.9),
                          c.crimson.withValues(alpha: 0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: c.isLight
                          ? [
                              BoxShadow(
                                color: c.gold.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: c.gold.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        const Text('🧬', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr?.get('dna_title') ?? "Sinema DNA'n",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.get('dna_banner_desc') ??
                                    'Zevkinin kimliğini keşfet.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (total >= 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SpringButton(
                  onTap: () {
                    final username =
                        ref.read(authProvider).user?['username'] as String?;
                    showGeneralDialog(
                      context: context,
                      barrierDismissible: false,
                      barrierColor: Colors.black,
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (ctx, anim1, anim2) {
                        return WrappedModal(stats: stats, username: username);
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF2E93), Color(0xFFFF8A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF2E93,
                          ).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr?.get('your_cinema_recap') ??
                                    'Your Cinema Recap!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.get('discover_your_cinema_journey_o') ??
                                    'Discover your cinema journey of the year.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 3. Movie Library Section
          if (watchlist.isNotEmpty ||
              (stats['ratedMovies'] != null &&
                  (stats['ratedMovies'] as List).isNotEmpty)) ...[
            SliverToBoxAdapter(
              child: _sectionHeader(
                context,
                c,
                tr?.get('profile_watchlist') ?? 'Kütüphanen',
              ),
            ),
            if (watchlist.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        tr?.get('profile_watchlist') ?? 'İZLEME LİSTESİ',
                        style: TextStyle(
                          color: c.dim,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
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
                          tr?.get('see_all') ?? 'See All',
                          style: TextStyle(
                            color: c.red,
                            fontSize: 11,
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
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
            if (stats['ratedMovies'] != null &&
                (stats['ratedMovies'] as List).isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    tr?.get('profile_history') ?? 'DEĞERLENDİRDİKLERİM',
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
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
                          (stats['ratedMovies'] as List)[i]
                              as Map<String, dynamic>;
                      final movie = item['movie'] as Movie;
                      final rating = item['rating'] as int;
                      return _RatedMovieCard(
                        movie: movie,
                        rating: rating,
                        onTap: () => _openDetail(context, ref, movie),
                        onDelete: () =>
                            _confirmDeleteRating(context, ref, movie),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ],

          // 4. Statistics Section
          if (total > 0) ...[
            SliverToBoxAdapter(
              child: _sectionHeader(
                context,
                c,
                tr?.get('profile_stats') ?? 'İstatistiklerin',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: c.isLight
                            ? Border.all(color: c.border, width: 1)
                            : null,
                        boxShadow: c.cardShadow,
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
                                    tr?.get('profile_rating') ?? 'Ratings',
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
                              tr?.get('profile_genres') ?? 'EN SEVDİĞİN TÜRLER',
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
                                            ? Border.all(
                                                color: c.border,
                                                width: 1,
                                              )
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
                    const SizedBox(height: 14),
                    _ratingDistribution(context, stats),
                  ],
                ),
              ),
            ),
          ],

          // 5. Social Section
          if (ref.watch(authProvider).isLoggedIn) ...[
            SliverToBoxAdapter(
              child: _sectionHeader(
                context,
                c,
                tr?.get('together_social_title') ?? 'Sosyal',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                        color: c.isLight
                            ? c.border
                            : Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      ),
                      boxShadow: c.cardShadow,
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
                                tr?.get('together_social_title') ??
                                    'Social & Friends',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ref.watch(authProvider).user?['username'] !=
                                        null
                                    ? '@${ref.watch(authProvider).user!['username']}'
                                    : (tr?.get(
                                            'see_taste_matches_manage_reque',
                                          ) ??
                                          'See taste matches, manage requests and activity feeds.'),
                                style: TextStyle(color: c.dim, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (ctx) {
                            final pendingCount = ref
                                .watch(socialProvider)
                                .pendingReceived
                                .length;
                            if (pendingCount > 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                            return Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: c.dim,
                              size: 14,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],

          // 6. Settings & Utilities Section
          SliverToBoxAdapter(
            child: _sectionHeader(
              context,
              c,
              tr?.get('settings_title') ?? 'Ayarlar & Tercihler',
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: const _FamilyModeCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: const SyncSection(),
            ),
          ),
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
                    boxShadow: c.cardShadow,
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
                              tr?.locale.languageCode == 'tr'
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
                              tr?.locale.languageCode == 'tr'
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
                    boxShadow: c.cardShadow,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tr?.get('profile_reset_title') ?? 'Tüm Verileri Sıfırla',
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
        boxShadow: c.cardShadow,
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
        boxShadow: c.cardShadow,
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
                  AppLocalizations.of(context)?.get('profile_family_mode') ??
                      'Aile Dostu Mod (PG-13)',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.get('filters_out_deadpool_euphoria_') ??
                      'Filters out Deadpool, Euphoria, and mature R-rated content.',
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
