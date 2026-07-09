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
import '../services/sync_service.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'taste_dna_screen.dart';
import 'my_reviews_screen.dart';
import 'blocked_users_screen.dart';
import '../widgets/spring_button.dart';
import '../widgets/wrapped_modal.dart';
import '../widgets/logout_confirm_dialog.dart';
import '../widgets/delete_account_dialog.dart';
import '../widgets/auth_conflict_dialog.dart';
import '../services/app_config.dart';
import 'profile/widgets/change_password_sheet.dart';
import 'profile/widgets/unlink_google_sheet.dart';
import 'profile/widgets/blocked_users_sheet.dart';

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

  Future<void> _handleGoogleSignIn(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    try {
      final result = await ref.read(authProvider.notifier).signInWithGoogle();
      if (!context.mounted) return;

      if (result.status == AuthStatus.success) {
        ref.invalidate(watchlistProvider);
        ref.invalidate(statsProvider);
      } else if (result.status == AuthStatus.conflict) {
        final resolution = await showAuthConflictDialog(context);
        if (resolution != null && context.mounted) {
          await ref
              .read(authProvider.notifier)
              .completeLogin(
                user: result.user!,
                tokens: result.tokens!,
                resolution: resolution,
              );
          ref.invalidate(watchlistProvider);
          ref.invalidate(statsProvider);
        } else {
          // İptal: sunucunun çoktan verdiği token çifti kullanılmayacak →
          // sunucuda iptal et ki yetim refresh token kalmasın.
          await ref
              .read(authProvider.notifier)
              .cancelPendingLogin(result.tokens);
        }
      } else if (result.status == AuthStatus.error) {
        final errKey = result.errorMessage ?? 'auth_err_login_failed';
        final message = AppLocalizations.of(context)?.get(errKey) ?? errKey;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: c.red),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final tr = AppLocalizations.of(context);
        final formatString = tr?.get('error_occurred_msg') ?? 'Error: {}';
        final message = formatString.replaceFirst('{}', e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: c.red),
        );
      }
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
      final ratingRecord = await PrefsService.getRating(movie.id, movie.isTV);
      final prevRating = ratingRecord?['rating'] as int?;
      await PrefsService.deleteRating(movie.id, movie.isTV);
      if (prevRating != null) {
        PrefsService.revertRecoOutcome(
          source: movie.recoSource ?? 'discover',
          liked: prevRating >= 2,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
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
        final userId = ref.read(authProvider).user?['id']?.toString();
        final dna = await ref
            .read(tasteDnaServiceProvider)
            .generate(userId: userId);

        final cachedData = await PrefsService.getCachedDna();
        final currentHash = cachedData?['hash'];
        final lastPublishedHash = await PrefsService.getLastPublishedDnaHash();

        if (currentHash != null && currentHash != lastPublishedHash) {
          await ref.read(apiServiceProvider).publishTasteDna(dna.toJson());
          await PrefsService.setLastPublishedDnaHash(currentHash);
          debugPrint("Background DNA auto-publish succeeded!");
        } else {
          debugPrint(
            "Background DNA auto-publish skipped (already up to date).",
          );
        }
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

    ref.listen<AsyncValue<Map<String, dynamic>>>(statsProvider, (prev, next) {
      if (next.hasValue && ref.read(authProvider).isAuthenticated) {
        final total = next.value?['total'] as int? ?? 0;
        final userId = ref.read(authProvider).user?['id']?.toString();
        if (total >= 5 &&
            (_lastPublishedRatingCount != total ||
                _lastPublishedUserId != userId)) {
          _lastPublishedRatingCount = total;
          _lastPublishedUserId = userId;
          _autoPublishDna(ref);
        }
      }
    });

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                    onPressed: () => showLogoutConfirmDialog(context, ref),
                    tooltip: tr?.get('auth_logout') ?? 'Çıkış Yap',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
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
            if (!isLoggedIn && AppConfig.googleSignInConfigured) ...[
              const SizedBox(height: 16),
              Divider(
                color: c.isLight
                    ? c.borderSoft
                    : Colors.white.withValues(alpha: 0.08),
                height: 1,
              ),
              const SizedBox(height: 14),
              SpringButton(
                onTap: auth.loading
                    ? null
                    : () => _handleGoogleSignIn(context, ref),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.isLight
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: c.isLight
                          ? c.border
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: auth.loading
                      ? Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.dim,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tr?.get('auth_google_button') ??
                                  'Google ile devam et',
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
            if (isLoggedIn) ...[
              const SizedBox(height: 12),
              const _SyncHeaderAction(),
            ],
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
    final ratedMovies = stats['ratedMovies'] as List<dynamic>? ?? [];
    final tr = AppLocalizations.of(context);
    final syncState = ref.watch(syncProvider);
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth.isLoggedIn;

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
          if (syncState == SyncStatus.error)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: c.red.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sync_problem_rounded, color: c.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr?.get('sync_error_message') ??
                              'Eşitleme başarısız oldu. Değişiklikleriniz bu cihazda güvende.',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(syncProvider.notifier)
                              .performSync()
                              .catchError((_) {});
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          tr?.get('sync_retry') ?? 'Tekrar Dene',
                          style: TextStyle(
                            color: c.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Header Row — araç ikonları (yenile, dil, tema, hakkında, web)
          // global üst bara/menüye taşındı; yenileme pull-to-refresh'te.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                tr?.get('tab_profile') ?? 'Profilim',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          // 1. User Header Card
          SliverToBoxAdapter(child: _userHeaderCard(context, ref, c)),

          // Google bağlantısını kaldır — kimlik kartının hemen altında:
          // oturumla ilgili işlemler (giriş/çıkış/bağlantı) tek blokta.
          if (isLoggedIn &&
              auth.user?['google_sub'] != null &&
              (auth.user!['google_sub'] as String?)?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) =>
                          UnlinkGoogleSheet(ref: ref, parentContext: context),
                    );
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
                            color: c.red.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.link_off_rounded,
                            color: c.red,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr?.get('google_unlink_title') ??
                                    'Google Bağlantısını Kaldır',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.get('google_unlink_desc') ??
                                    'Devam etmek için hesap parolanızı girin.',
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

          // 2. Kütüphane vitrini — son 10 öğe + "Tümünü Gör" uç kartı.
          // Arşivin tamamı LibraryScreen'de (showroom); ray artık listenin
          // tamamını basmıyor (200 öğe = 200 kaydırma sorunu). Profilin
          // günlük kullanım nedeni burası olduğu için en üste alındı.
          if (watchlist.isNotEmpty || ratedMovies.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _sectionHeader(
                context,
                c,
                tr?.get('library_title') ?? 'Kütüphanen',
              ),
            ),
            if (watchlist.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _railLabel(
                  context,
                  c,
                  label: tr?.get('profile_watchlist') ?? 'İZLEME LİSTESİ',
                  count: watchlist.length,
                  onSeeAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LibraryScreen(initialTab: 0),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 225,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final m in watchlist.take(10))
                        _WatchlistCard(
                          movie: m,
                          onTap: () => _openDetail(context, ref, m),
                          onRemove: () {
                            ref
                                .read(watchlistProvider.notifier)
                                .remove(m.id, m.isTV);
                          },
                        ),
                      if (watchlist.length > 10)
                        _SeeAllCard(
                          remaining: watchlist.length - 10,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LibraryScreen(initialTab: 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
            if (ratedMovies.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _railLabel(
                  context,
                  c,
                  label: tr?.get('profile_history') ?? 'DEĞERLENDİRDİKLERİM',
                  count: ratedMovies.length,
                  onSeeAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LibraryScreen(initialTab: 1),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 225,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final item
                          in ratedMovies.take(10).cast<Map<String, dynamic>>())
                        _RatedMovieCard(
                          movie: item['movie'] as Movie,
                          rating: item['rating'] as int,
                          isPrivate: (item['is_private'] as int? ?? 0) == 1,
                          onTap: () =>
                              _openDetail(context, ref, item['movie'] as Movie),
                          onDelete: () => _confirmDeleteRating(
                            context,
                            ref,
                            item['movie'] as Movie,
                          ),
                        ),
                      if (ratedMovies.length > 10)
                        _SeeAllCard(
                          remaining: ratedMovies.length - 10,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LibraryScreen(initialTab: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Yorumlarım: yazılan tüm yorumların toplu görünümü/yönetimi.
              // Raylar arasında kaybolmasın diye büyük ayar kartı stilinde,
              // altın vurgulu ve yorum sayısı rozetli.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SpringButton(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyReviewsScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: c.gold.withValues(alpha: 0.35),
                          width: 1,
                        ),
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
                              Icons.rate_review_rounded,
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
                                  tr?.get('my_reviews_title') ?? 'Yorumlarım',
                                  style: TextStyle(
                                    color: c.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr?.get('my_reviews_subtitle') ??
                                      'Yazdığın tüm yorumlar tek yerde',
                                  style: TextStyle(color: c.dim, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: PrefsService.getCommentedRatings(),
                            builder: (_, snap) {
                              final count = snap.data?.length ?? 0;
                              if (count == 0) return const SizedBox.shrink();
                              return Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: c.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: c.gold.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: c.gold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            },
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.dim),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
            ],
          ],

          // 3. Sinema Kimliğin — Zevk DNA'sı + istatistikler tek başlık
          // altında: ikisi de "ben nasıl bir izleyiciyim?" sorusunu yanıtlar.
          SliverToBoxAdapter(
            child: _sectionHeader(
              context,
              c,
              tr?.get('profile_cinema_identity') ?? 'Sinema Kimliğin',
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

          // 4. Statistics (Sinema Kimliğin başlığı altında devam eder)
          if (total > 0) ...[
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

          // Sosyal bölümü kaldırıldı: artık hem global menüde hem Birlikte
          // sekmesinde yaşıyor — üçüncü kopyaya gerek yok.

          // 5. Settings & Utilities Section
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

          if (isLoggedIn)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: context.c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) =>
                          BlockedUsersSheet(parentContext: context),
                    );
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
                            color: c.red.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.block_rounded,
                            color: c.red,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr?.get('blocked_users_title') ??
                                    'Engellenen Kullanıcılar',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.get('blocked_users_subtitle') ??
                                    'Yorumlarını ve aktivitelerini gizlediğin kişiler',
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

          if (isLoggedIn && auth.user?['google_sub'] == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) =>
                          ChangePasswordSheet(ref: ref, parentContext: context),
                    );
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
                            Icons.lock_reset_rounded,
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
                                tr?.get('change_password_title') ??
                                    'Şifre Değiştir',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.locale.languageCode == 'tr'
                                    ? 'Hesap şifrenizi güncelleyin'
                                    : 'Update your account password',
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

          // Engellenen kullanıcılar: yalnızca girişli kullanıcıda anlamlı
          // (engelleme sunucu tarafında yaşar).
          if (isLoggedIn)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
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
                            Icons.block_rounded,
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
                                tr?.get('blocked_users_title') ??
                                    'Engellenen Kullanıcılar',
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr?.get('blocked_users_subtitle') ??
                                    'Engellediğin kullanıcıları yönet',
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

          // Google bağlantısını kaldırma kartı buradan kimlik kartının
          // altına taşındı — oturumla ilgili işlemler bir arada dursun.
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
          // 6. Tehlike Bölgesi — iki yıkıcı işlem tek çerçevede, açık
          // başlıkla. Eskiden aralarında 40px başıboş boşluk vardı; onay
          // diyalogları yanlış dokunuşu zaten engelliyor, buradaki iş
          // gruplama ve görünürlük.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: c.red.withValues(alpha: 0.35),
                    width: 1,
                  ),
                  boxShadow: c.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: c.red,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (tr?.get('danger_zone') ?? 'Tehlike Bölgesi')
                              .toUpperCase(),
                          style: TextStyle(
                            color: c.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _dangerButton(
                      c,
                      icon: Icons.restart_alt_rounded,
                      label:
                          tr?.get('profile_reset_title') ??
                          'Tüm Verileri Sıfırla',
                      onTap: () => _confirmReset(context, ref),
                    ),
                    // Google Play politikası: hesap oluşturulabilen
                    // uygulamalarda kalıcı hesap silme yolu zorunlu.
                    if (isLoggedIn) ...[
                      const SizedBox(height: 8),
                      _dangerButton(
                        c,
                        icon: Icons.delete_forever_rounded,
                        label: tr?.get('auth_delete_account') ?? 'Hesabı Sil',
                        onTap: () => showDeleteAccountDialog(context, ref),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerButton(
    ThemePalette c, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.red.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c.red, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: c.red,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ray üstü etiket: "İZLEME LİSTESİ · 34" + "Tümünü Gör".
  Widget _railLabel(
    BuildContext context,
    ThemePalette c, {
    required String label,
    required int count,
    required VoidCallback onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Text(
            '${label.toUpperCase()} · $count',
            style: TextStyle(
              color: c.dim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          // Belirgin hap buton: düz metin hâli gözden kaçıyordu.
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onSeeAll();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: c.red.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('see_all') ??
                        'Tümünü Gör',
                    style: TextStyle(
                      color: c.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: c.red, size: 13),
                ],
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

/// Ray sonu "showroom" kapısı: kalan öğe sayısı + Tümünü Gör.
/// Vitrin 10 öğede kesildiği için arşivin geri kalanına buradan geçilir.
class _SeeAllCard extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;
  const _SeeAllCard({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 126,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: c.gold.withValues(alpha: 0.06),
                  border: Border.all(
                    color: c.gold.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+$remaining',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)?.get('see_all') ??
                          'Tümünü Gör',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Poster kartlarındaki başlık + yıl satırlarıyla hizalanır.
            const SizedBox(height: 6),
            const Text(' ', style: TextStyle(fontSize: 13.5)),
            const Text(' ', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
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
  final bool isPrivate;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _RatedMovieCard({
    required this.movie,
    required this.rating,
    this.isPrivate = false,
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
                    if (isPrivate)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.65),
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            color: c.gold,
                            size: 14,
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

class _SyncHeaderAction extends ConsumerStatefulWidget {
  const _SyncHeaderAction();

  @override
  ConsumerState<_SyncHeaderAction> createState() => _SyncHeaderActionState();
}

class _SyncHeaderActionState extends ConsumerState<_SyncHeaderAction> {
  bool _syncing = false;
  String? _syncTimeStr;

  @override
  void initState() {
    super.initState();
    _loadSyncTime();
  }

  Future<void> _loadSyncTime() async {
    final timestamp = await PrefsService.getLastSyncTime();
    if (timestamp == 0) {
      if (mounted) setState(() => _syncTimeStr = null);
      return;
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    if (mounted) {
      setState(() => _syncTimeStr = "$day.$month $hour:$min");
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    HapticFeedback.lightImpact();
    try {
      await ref.read(syncServiceProvider).sync();
      await _loadSyncTime();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('sync_success') ??
                  'Successfully synced',
            ),
            backgroundColor: context.c.gold,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('auth_err_generic') ??
                  'Bir hata oluştu: $e',
            ),
            backgroundColor: context.c.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return Column(
      children: [
        Divider(
          color: c.isLight
              ? c.borderSoft
              : Colors.white.withValues(alpha: 0.08),
          height: 1,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _syncTimeStr != null
                    ? "${tr?.get('sync_last') ?? 'Last synced: '}$_syncTimeStr"
                    : (tr?.get('sync_desc') ?? 'Cloud sync active'),
                style: TextStyle(color: c.dim, fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _runSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: _syncing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 14),
                label: Text(
                  tr?.get('sync_now') ?? 'Sync Now',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
