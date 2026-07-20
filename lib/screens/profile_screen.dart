import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../services/localization_service.dart';
import '../providers/watchlist_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import 'movie_detail_sheet.dart';
import 'watchlist_screen.dart';
import '../services/sync_service.dart';
import 'onboarding_screen.dart';
import 'blocked_users_screen.dart';
import '../widgets/app_toast.dart';
import '../widgets/delete_account_dialog.dart';
import '../widgets/auth_loading_overlay.dart';
import 'profile/widgets/change_password_sheet.dart';
import 'profile/widgets/unlink_google_sheet.dart';
import 'profile/widgets/unlink_apple_sheet.dart';
import 'profile/widgets/user_header_card.dart';
import 'profile/widgets/profile_rail_cards.dart';
import 'profile/widgets/family_mode_card.dart';
import 'profile/widgets/settings_nav_card.dart';
import 'profile/widgets/my_reviews_card.dart';
import 'profile/widgets/cinema_identity_cards.dart';
import 'profile/widgets/stats_cards.dart';
import 'profile/widgets/received_recommendations_card.dart';
import 'profile/widgets/sent_recommendations_card.dart';
import 'profile/widgets/danger_zone_card.dart';
import 'profile/widgets/sync_error_banner.dart';

/// Profil sekmesi orkestratörü: sliver düzenini kurar, veri sağlayıcıları
/// dinler ve yıkıcı işlemlerin onay akışlarını yönetir. Görsel parçalar
/// profile/widgets/ altındaki dosyalarda yaşar.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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
      await ref.read(authProvider.notifier).wipeAllData();
      ref.invalidate(syncProvider);
      if (context.mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context)?.get('all_data_reset') ??
              'Tüm veriler sıfırlandı.',
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
    final userId = ref.read(authProvider).user?['id']?.toString();
    final dnaService = ref.read(tasteDnaServiceProvider);
    final apiService = ref.read(apiServiceProvider);
    Future.microtask(() async {
      try {
        final dna = await dnaService.generate(userId: userId);

        final cachedData = await PrefsService.getCachedDna();
        final currentHash = cachedData?['hash'];
        final lastPublishedHash = await PrefsService.getLastPublishedDnaHash();

        if (currentHash != null && currentHash != lastPublishedHash) {
          await apiService.publishTasteDna(dna.toJson());
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

  Future<void> _restartOnboarding(BuildContext context) async {
    await PrefsService.resetOnboarding();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final auth = ref.watch(authProvider);
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

    return Stack(
      children: [
        Scaffold(
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
        ),
        AuthLoadingOverlay(
          visible: auth.loading,
          messageKey: auth.loadingMessageKey,
        ),
      ],
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
          ref.read(authProvider.notifier).refreshUser(),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          if (syncState == SyncStatus.error)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SyncErrorBanner(),
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

          // 1. User Header Card — profil, çıkış ve senkron (Google bağlantısı Ayarlar'da)
          const SliverToBoxAdapter(child: UserHeaderCard()),

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
                        WatchlistCard(
                          movie: m,
                          onTap: () => _openDetail(context, ref, m),
                          onRemove: () {
                            ref
                                .read(watchlistProvider.notifier)
                                .remove(m.id, m.isTV);
                          },
                        ),
                      if (watchlist.length > 10)
                        SeeAllCard(
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
                        RatedMovieCard(
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
                        SeeAllCard(
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
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
            ],
          ],

          if (isLoggedIn) ...[
            SliverToBoxAdapter(
              child: _sectionHeader(
                context,
                c,
                tr?.get('profile_interactions') ?? 'Etkileşimlerim',
              ),
            ),
            if (ratedMovies.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: MyReviewsCard(),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SentRecommendationsCard(),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ReceivedRecommendationsCard(),
              ),
            ),
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
                child: DnaLockedCard(total: total),
              ),
            ),
          if (total >= 5)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: DnaBanner(),
              ),
            ),
          if (total >= 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: WrappedBanner(stats: stats),
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
                    StatsOverviewCard(total: total, topGenres: topGenres),
                    const SizedBox(height: 14),
                    RatingDistributionCard(stats: stats),
                  ],
                ),
              ),
            ),
          ],

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SettingsNavCard(
                icon: Icons.insights_rounded,
                iconColor: c.gold,
                iconBackground: c.gold.withValues(alpha: 0.15),
                title:
                    tr?.get('profile_restart_taste_title') ??
                    'Zevk Analizini Yeniden Başlat',
                subtitle:
                    tr?.get('profile_restart_taste_subtitle') ??
                    'Film & dizi önerilerini zevkine göre ayarla',
                onTap: () => _restartOnboarding(context),
              ),
            ),
          ),

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
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FamilyModeCard(),
            ),
          ),

          if (isLoggedIn &&
              auth.user?['google_sub'] == null &&
              auth.user?['apple_sub'] == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SettingsNavCard(
                  icon: Icons.lock_reset_rounded,
                  iconColor: c.gold,
                  iconBackground: c.gold.withValues(alpha: 0.15),
                  title: tr?.get('change_password_title') ?? 'Şifre Değiştir',
                  subtitle: tr?.locale.languageCode == 'tr'
                      ? 'Hesap şifrenizi güncelleyin'
                      : 'Update your account password',
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) => ChangePasswordSheet(ref: ref),
                    );
                  },
                ),
              ),
            ),

          // Engellenen kullanıcılar: yalnızca girişli kullanıcıda anlamlı
          // (engelleme sunucu tarafında yaşar).
          if (isLoggedIn)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SettingsNavCard(
                  icon: Icons.block_rounded,
                  iconColor: c.gold,
                  iconBackground: c.gold.withValues(alpha: 0.15),
                  title:
                      tr?.get('blocked_users_title') ??
                      'Engellenen Kullanıcılar',
                  subtitle:
                      tr?.get('blocked_users_subtitle') ??
                      'Engellediğin kullanıcıları yönet',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),

          if (isLoggedIn &&
              auth.user?['google_sub'] != null &&
              (auth.user!['google_sub'] as String?)?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SettingsNavCard(
                  icon: Icons.link_off_rounded,
                  iconColor: c.red,
                  iconBackground: c.red.withValues(alpha: 0.12),
                  title:
                      tr?.get('google_unlink_title') ??
                      'Google Bağlantısını Kaldır',
                  subtitle:
                      tr?.get('google_unlink_desc') ??
                      'Devam etmek için hesap parolanızı girin.',
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) => UnlinkGoogleSheet(ref: ref),
                    );
                  },
                ),
              ),
            ),

          if (isLoggedIn &&
              auth.user?['apple_sub'] != null &&
              (auth.user!['apple_sub'] as String?)?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SettingsNavCard(
                  icon: Icons.link_off_rounded,
                  iconColor: c.red,
                  iconBackground: c.red.withValues(alpha: 0.12),
                  title:
                      tr?.get('apple_unlink_title') ??
                      'Apple Bağlantısını Kaldır',
                  subtitle:
                      tr?.get('apple_unlink_desc') ??
                      'Devam etmek için hesap parolanızı girin.',
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: c.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) => UnlinkAppleSheet(ref: ref),
                    );
                  },
                ),
              ),
            ),

          // 6. Tehlike Bölgesi
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: DangerZoneCard(
                isLoggedIn: isLoggedIn,
                onReset: () => _confirmReset(context, ref),
                onDeleteAccount: () => showDeleteAccountDialog(context, ref),
              ),
            ),
          ),
        ],
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
}
