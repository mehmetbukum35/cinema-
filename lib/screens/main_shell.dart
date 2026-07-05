import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../providers/social_provider.dart';
import 'browse_screen.dart';
import 'swipe_screen.dart';
import 'together_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;

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

  @override
  Widget build(BuildContext context) {
    final pal = context.c;
    final isOffline = ref.watch(offlineProvider);
    // "Birlikte" sekmesi rozeti: bekleyen istek + okunmamış öneri.
    final social = ref.watch(socialProvider);
    final togetherBadge =
        social.pendingReceived.length + social.unseenRecommendations;
    return Scaffold(
      backgroundColor: pal.bg,
      body: Column(
        children: [
          if (isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)?.locale.languageCode == 'tr'
                        ? 'Çevrimdışısınız — Değişiklikleriniz senkronize edilecek'
                        : 'You are offline — Your changes will be synced',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                // TickerMode: görünmeyen sekmelerin TÜM animasyonlarını (aurora,
                // shimmer vb.) dondurur — kapsamlı pil koruması.
                TickerMode(
                  enabled: _tab == 0,
                  child: BrowseScreen(
                    onOpenProfile: () => _onTabChange(4),
                  ),
                ),
                TickerMode(
                  enabled: _tab == 1,
                  child: const SwipeScreen(),
                ),
                TickerMode(
                  enabled: _tab == 2,
                  child: const TogetherScreen(),
                ),
                TickerMode(
                  enabled: _tab == 3,
                  child: const SearchScreen(),
                ),
                TickerMode(
                  enabled: _tab == 4,
                  child: const ProfileScreen(),
                ),
              ],
            ),
          ),
        ],
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
