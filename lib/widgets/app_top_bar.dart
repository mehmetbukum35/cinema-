import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';
import '../services/prefs_service.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../screens/movie_detail_sheet.dart';
import '../screens/social_screen.dart';
import 'about_sheet.dart';

/// Her sekmenin üstünde duran global bar: marka + sürpriz zarı + rozetli
/// avatar. Avatar, Sosyal / Tercihler / Hesap gruplu açılır menüyü açar.
/// Keşfet başlığındaki 7 dağınık ikonun yerini alır (yenile: pull-to-refresh
/// zaten var; dil/tema/hakkında/web profili: menüye taşındı).
class AppTopBar extends ConsumerStatefulWidget {
  /// Menüdeki "Profilim" için sekme değiştirme (MainShell verir).
  final VoidCallback? onOpenProfile;
  const AppTopBar({super.key, this.onOpenProfile});

  @override
  ConsumerState<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends ConsumerState<AppTopBar> {
  final _rng = Random();
  bool _luckyBusy = false;

  /// Sürpriz/zar: zevke uygun rastgele film (Keşfet'ten taşındı — "bana bir
  /// şey öner" niyeti her sekmede geçerli).
  Future<void> _luckyPick() async {
    if (_luckyBusy) return;
    HapticFeedback.lightImpact();

    final isFirst = await PrefsService.isFirstTimeDice();
    if (isFirst && mounted) {
      final tr = AppLocalizations.of(context);
      final c = context.c;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            tr?.get('browse_surprise_title') ?? 'Lucky Pick 🎲',
            style: TextStyle(
              color: c.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            tr?.get('browse_surprise_desc') ??
                'This dice button selects a random movie tailored to your tastes based on the films you have rated. Use it whenever you want to be surprised!',
            style: TextStyle(color: c.dim, fontSize: 13.5, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                tr?.get('got_it') ?? 'Got it',
                style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    _luckyBusy = true;
    try {
      final service = ref.read(tmdbServiceProvider);
      final likedGenres = await PrefsService.getLikedGenreIds();
      var results = await service.discoverByGenres(likedGenres, isTV: false);
      if (results.isEmpty) {
        results = await service.getPopular(isTV: false);
      }
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.get('browse_conn_error') ??
                  'Bağlantı hatası veya sonuç bulunamadı.',
            ),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      final movie = results[_rng.nextInt(results.length)];
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => MovieDetailSheet(movie: movie, service: service),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red),
      );
    } finally {
      _luckyBusy = false;
    }
  }

  String _profileInitial(AuthState authState) {
    final user = authState.user;
    final name = (user?['display_name'] as String?)?.trim();
    final username = (user?['username'] as String?)?.trim();
    final source = (name != null && name.isNotEmpty)
        ? name
        : (username != null && username.isNotEmpty ? username : '');
    return source.isEmpty ? '?' : source[0].toUpperCase();
  }

  Future<void> _shareProfile() async {
    HapticFeedback.lightImpact();
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    final tr = AppLocalizations.of(context);
    final username = (auth.user?['username'] as String?)?.trim();
    if (username == null || username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr?.get('profile_share_no_username') ??
                'Profilinizi paylaşmak için kullanıcı adı belirleyin.',
          ),
        ),
      );
      widget.onOpenProfile?.call();
      return;
    }

    final locale = ref.read(localeProvider);
    final isTr = locale.languageCode == 'tr';
    final profileUrl = ApiService.webProfileUrl(
      username,
      lang: isTr ? 'tr' : 'en',
    );
    final message =
        tr?.get('profile_share_message').replaceAll('{}', profileUrl) ??
        'Follow me on What to Watch! Check out my watchlist and favorites here: $profileUrl';
    await Share.share(message);
  }

  void _openMenu() {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          AppLocalizations.of(context)?.get('semantics_close') ?? 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) =>
          _AppMenu(parentContext: context, onOpenProfile: widget.onOpenProfile),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            alignment: Alignment.topRight,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final social = ref.watch(socialProvider);
    final badge = auth.isAuthenticated
        ? social.pendingReceived.length + social.unseenRecommendations
        : 0;

    return Container(
      color: c.bg,
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'CINEMA',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                TextSpan(
                  text: '+',
                  style: TextStyle(
                    color: c.red,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Semantics(
            label: tr?.get('browse_surprise') ?? 'Sürpriz film',
            button: true,
            child: IconButton(
              icon: Icon(Icons.casino_rounded, color: c.dim, size: 22),
              onPressed: _luckyPick,
              tooltip: tr?.get('browse_surprise') ?? 'Sürpriz film',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
            ),
          ),
          if (auth.isAuthenticated)
            Semantics(
              label: tr?.get('profile_share') ?? 'Paylaş',
              button: true,
              child: IconButton(
                icon: Icon(Icons.share_rounded, color: c.dim, size: 22),
                onPressed: _shareProfile,
                tooltip: tr?.get('profile_share') ?? 'Paylaş',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
              ),
            ),
          Semantics(
            label: tr?.get('menu_account') ?? 'Menü',
            button: true,
            child: GestureDetector(
              onTap: _openMenu,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: auth.isAuthenticated
                              ? CinemaGradients.crimson
                              : null,
                          color: auth.isAuthenticated ? null : c.surface,
                          border: auth.isAuthenticated
                              ? null
                              : Border.all(color: c.border, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: auth.isAuthenticated
                            ? Text(
                                _profileInitial(auth),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                color: c.dim,
                                size: 18,
                              ),
                      ),
                      if (badge > 0)
                        Positioned(
                          right: -4,
                          top: -3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(minWidth: 15),
                            decoration: BoxDecoration(
                              color: c.red,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: c.bg, width: 1.5),
                            ),
                            child: Text(
                              badge > 9 ? '9+' : '$badge',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
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
        ],
      ),
    );
  }
}

/// Sağ üstten açılan gruplu menü paneli.
class _AppMenu extends ConsumerWidget {
  /// Menü kapandıktan sonra navigasyon bu context üzerinden yapılır
  /// (dialog context'i pop edilince ölür).
  final BuildContext parentContext;
  final VoidCallback? onOpenProfile;
  const _AppMenu({required this.parentContext, this.onOpenProfile});

  void _close(BuildContext ctx) => Navigator.of(ctx).pop();

  void _pushSocialTab(BuildContext ctx, int tab) {
    _close(ctx);
    Navigator.of(
      parentContext,
    ).push(MaterialPageRoute(builder: (_) => SocialScreen(initialTab: tab)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final social = ref.watch(socialProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final isTr = locale.languageCode == 'tr';
    final username = auth.user?['username'] as String?;

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 48, right: 12),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 264,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: c.isLight ? 0.18 : 0.55,
                    ),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(6),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (auth.isAuthenticated) ...[
                      _groupLabel(c, tr?.get('menu_social') ?? 'Sosyal'),
                      _row(
                        c,
                        icon: Icons.groups_rounded,
                        label: tr?.get('menu_my_friends') ?? 'Arkadaşlarım',
                        onTap: () => _pushSocialTab(context, 0),
                      ),
                      _row(
                        c,
                        icon: Icons.mail_rounded,
                        label:
                            tr?.get('menu_requests') ?? 'Arkadaşlık İstekleri',
                        trailing: social.pendingReceived.isNotEmpty
                            ? _pill(
                                c,
                                social.pendingReceived.length,
                                color: c.red,
                              )
                            : null,
                        onTap: () => _pushSocialTab(context, 1),
                      ),
                      _row(
                        c,
                        icon: Icons.timeline_rounded,
                        label: tr?.get('menu_activity') ?? 'Aktivite Akışı',
                        trailing: social.unseenRecommendations > 0
                            ? _pill(
                                c,
                                social.unseenRecommendations,
                                color: c.gold,
                                dark: true,
                              )
                            : null,
                        onTap: () => _pushSocialTab(context, 2),
                      ),
                      _row(
                        c,
                        icon: Icons.emoji_events_rounded,
                        label: tr?.get('menu_top_lists') ?? 'Top Listeler',
                        onTap: () => _pushSocialTab(context, 3),
                      ),
                      _divider(c),
                    ],
                    _groupLabel(c, tr?.get('menu_preferences') ?? 'Tercihler'),
                    _row(
                      c,
                      icon: isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      label: tr?.get('theme_switch') ?? 'Tema',
                      trailing: _segmented(
                        c,
                        left: tr?.get('theme_dark') ?? 'Koyu',
                        right: tr?.get('theme_light') ?? 'Açık',
                        leftOn: isDark,
                        onLeft: () => ref
                            .read(themeModeProvider.notifier)
                            .setMode(ThemeMode.dark),
                        onRight: () => ref
                            .read(themeModeProvider.notifier)
                            .setMode(ThemeMode.light),
                      ),
                    ),
                    _row(
                      c,
                      icon: Icons.language_rounded,
                      label: tr?.get('change_language') ?? 'Dil',
                      trailing: _segmented(
                        c,
                        left: 'TR',
                        right: 'EN',
                        leftOn: isTr,
                        onLeft: () =>
                            ref.read(localeProvider.notifier).setLocale('tr'),
                        onRight: () =>
                            ref.read(localeProvider.notifier).setLocale('en'),
                      ),
                    ),
                    _divider(c),
                    _groupLabel(c, tr?.get('menu_account') ?? 'Hesap'),
                    _row(
                      c,
                      icon: Icons.person_rounded,
                      label: tr?.get('menu_my_profile') ?? 'Profilim',
                      onTap: () {
                        _close(context);
                        onOpenProfile?.call();
                      },
                    ),
                    if (auth.isAuthenticated &&
                        username != null &&
                        username.isNotEmpty)
                      _row(
                        c,
                        icon: Icons.public_rounded,
                        label: tr?.get('web_profile') ?? 'Web Profilim',
                        trailing: Icon(
                          Icons.open_in_new_rounded,
                          color: c.textFaint,
                          size: 14,
                        ),
                        onTap: () async {
                          _close(context);
                          final url = Uri.parse(
                            ApiService.webProfileUrl(
                              username,
                              lang: isTr ? 'tr' : 'en',
                            ),
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    _row(
                      c,
                      icon: Icons.info_outline_rounded,
                      label: tr?.get('profile_about') ?? 'Hakkında',
                      onTap: () {
                        _close(context);
                        showAboutSheet(parentContext);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(ThemePalette c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: c.textFaint,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
      ),
    ),
  );

  Widget _divider(ThemePalette c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Divider(color: c.borderSoft, height: 1),
  );

  Widget _pill(
    ThemePalette c,
    int count, {
    required Color color,
    bool dark = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _segmented(
    ThemePalette c, {
    required String left,
    required String right,
    required bool leftOn,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    final selectedBg = c.isLight
        ? c.gold.withValues(alpha: 0.24)
        : c.gold.withValues(alpha: 0.18);
    final selectedBorder = c.gold.withValues(alpha: c.isLight ? 0.72 : 0.58);

    Widget seg(String label, bool on, VoidCallback onTap) => GestureDetector(
      onTap: () {
        if (!on) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: on ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: on ? selectedBorder : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? c.gold : c.textFaint,
            fontSize: 10.5,
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: on ? 0.25 : 0,
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.isLight ? c.bgWarm : c.card,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.border, width: 1),
      ),
      padding: const EdgeInsets.all(1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(left, leftOn, onLeft), seg(right, !leftOn, onRight)],
      ),
    );
  }

  Widget _row(
    ThemePalette c, {
    required IconData icon,
    required String label,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap();
            },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: c.dim, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
