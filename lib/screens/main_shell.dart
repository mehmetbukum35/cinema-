import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/couch_provider.dart';
import '../providers/social_provider.dart';
import '../utils/username_helper.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_toast.dart';
import 'browse_screen.dart';
import 'swipe_screen.dart';
import 'together_screen.dart';
import 'couch_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;
  bool _usernamePromptShown = false;
  int? _handledCouchResumeId;

  static const _items = [
    (Icons.home_rounded, 'tab_browse'),
    (Icons.star_rounded, 'tab_swipe'),
    (Icons.groups_rounded, 'tab_together'),
    (Icons.search_rounded, 'tab_search'),
    (Icons.person_rounded, 'tab_profile'),
  ];

  void _onTabChange(int index) {
    if (index == _tab) {
      if (index == 0) {
        ref.read(browseScrollTriggerProvider.notifier).state++;
      }
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _tab = index);
  }

  void _maybePromptUsername() {
    if (!mounted || _usernamePromptShown) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated || !needsUsername(auth.user)) return;
    _usernamePromptShown = true;
    showUsernamePromptIfNeeded(context, ref);
  }

  Future<void> _checkCouchOnLaunch() async {
    if (!mounted || !ref.read(authProvider).isAuthenticated) return;
    await ref.read(couchProvider.notifier).checkActive();
    if (!mounted) return;
    _maybeResumeCouch(ref.read(couchProvider));
  }

  void _maybeResumeCouch(CouchState couch) {
    final session = couch.session;
    if (session == null || _handledCouchResumeId == session.id) return;

    final tr = AppLocalizations.of(context);
    if (couch.hasPendingInvite) {
      _handledCouchResumeId = session.id;
      final name = session.friendName;
      showAppSnackBar(
        context,
        tr?.get('couch_invite_waiting').replaceAll('{}', name) ??
            '$name seni bekliyor!',
        duration: const Duration(seconds: 8),
        actionLabel: tr?.get('couch_live_title') ?? 'Birlikte Seç',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CouchScreen())),
      );
    } else if (session.status == 'active' || session.status == 'matched') {
      _handledCouchResumeId = session.id;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CouchScreen()));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptUsername();
      _checkCouchOnLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.c;
    final isOffline = ref.watch(offlineProvider);

    ref.listen(authProvider, (prev, next) {
      if (!next.isAuthenticated) {
        _usernamePromptShown = false;
        _handledCouchResumeId = null;
        return;
      }
      final becameAuthenticated = prev == null || !prev.isAuthenticated;
      final userChanged = prev?.user?['id'] != next.user?['id'];
      if (becameAuthenticated || userChanged) {
        _handledCouchResumeId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkCouchOnLaunch();
        });
      }
      if ((becameAuthenticated || userChanged) && needsUsername(next.user)) {
        _usernamePromptShown = false;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybePromptUsername(),
        );
      }
    });

    // "Birlikte" sekmesi rozeti: bekleyen istek + okunmamış öneri + kanepe daveti.
    final social = ref.watch(socialProvider);
    final couch = ref.watch(couchProvider);
    final togetherBadge =
        social.pendingReceived.length +
        social.unseenRecommendations +
        (couch.hasPendingInvite ? 1 : 0);
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (isOffline)
              Container(
                width: double.infinity,
                color: Colors.orange.shade800,
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 16,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(
                              context,
                            )?.get('you_are_offline_your_changes_w') ??
                            'Offline Mode — Your data will be synced at the first opportunity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Global üst bar: her sekmede aynı yerde durur (zar + rozetli
            // avatar menüsü). Keşfet başlığındaki dağınık ikon sırasının yerine.
            AppTopBar(onOpenProfile: () => _onTabChange(4)),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  // TickerMode: görünmeyen sekmelerin TÜM animasyonlarını (aurora,
                  // shimmer vb.) dondurur — kapsamlı pil koruması.
                  TickerMode(enabled: _tab == 0, child: const BrowseScreen()),
                  TickerMode(enabled: _tab == 1, child: const SwipeScreen()),
                  TickerMode(enabled: _tab == 2, child: const TogetherScreen()),
                  TickerMode(enabled: _tab == 3, child: const SearchScreen()),
                  TickerMode(enabled: _tab == 4, child: const ProfileScreen()),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pal.isLight
                ? [pal.surface, pal.navBg]
                : const [Color(0xF2121218), AppColors.navBg],
          ),
          border: Border(top: BorderSide(color: pal.borderSoft, width: 1)),
          boxShadow: [
            BoxShadow(
              color: pal.isLight
                  ? const Color(0x14000000)
                  : const Color(0x66000000),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: LayoutBuilder(
              builder: (context, c) {
                final itemW = c.maxWidth / _items.length;
                return Stack(
                  children: [
                    // Hareketli üst indikatör (akıcı şekilde aktif sekmeye kayar)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: _tab * itemW,
                      top: 0,
                      width: itemW,
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: CinemaGradients.crimson,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: CinemaShadows.glow(
                              AppColors.red,
                              strength: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Aktif sekme arkası yumuşak glow
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: _tab * itemW,
                      top: 0,
                      bottom: 0,
                      width: itemW,
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                pal.red.withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(_items.length, (i) {
                        final (icon, labelKey) = _items[i];
                        final label =
                            AppLocalizations.of(context)?.get(labelKey) ??
                            labelKey;
                        return _NavItem(
                          icon: icon,
                          label: label,
                          active: _tab == i,
                          badge: i == 2 ? togetherBadge : 0,
                          onTap: () => _onTabChange(i),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.c;
    final color = active ? pal.red : pal.textPassive;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: active ? 1.18 : 1.0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 24),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(minWidth: 15),
                        decoration: BoxDecoration(
                          color: pal.red,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: pal.navBg, width: 1.5),
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
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
