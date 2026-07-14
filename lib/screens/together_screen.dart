import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/couch_provider.dart';
import '../providers/social_provider.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_button.dart';
import 'couch_screen.dart';
import 'match_screen.dart';
import 'social_screen.dart';

/// "Birlikte" hub'ı — Bento grid dashboard.
/// Tamamı sosyal 3 hedefi kart olarak sunar: en üstte geniş "Sosyal" hero
/// kartı (en sık dönülen yer), altında kompakt eşleştirme modları.
/// ("Benzer Film Bul" sosyal olmadığı için Ara ekranına taşındı.)
/// Her kart ilgili ekranı geri-butonlu tam ekran olarak açar (task akışı).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key});

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  @override
  void initState() {
    super.initState();
    // Bekleyen "Birlikte Seç" daveti var mı? (kartta rozet gösterilir)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(couchProvider.notifier).checkActive();
      }
    });
  }

  void _push(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final social = ref.watch(socialProvider);
    final socialBadge =
        social.pendingReceived.length + social.unseenRecommendations;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // ── Başlık ────────────────────────────────────────────────────
            Text(
              tr?.get('tab_together') ?? 'Birlikte',
              style: TextStyle(
                color: c.ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr?.get('together_desc') ??
                  'Discover, match and share with friends.',
              style: TextStyle(color: c.dim, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // ── Hero: Sosyal & Arkadaşlar ─────────────────────────────────
            _heroCard(
              c: c,
              title: tr?.get('together_social_title') ?? 'Social & Friends',
              subtitle:
                  tr?.get('together_social_desc') ??
                  'Friends, requests and activity feed',
              icon: Icons.groups_rounded,
              badge: socialBadge,
              onTap: () => _push(const SocialScreen()),
            ),
            const SizedBox(height: 12),

            // ── Birlikte Seç (CANLI): iki telefon, aynı deste, ilk ortak
            // beğeni kazanır. Bekleyen davet varsa kart bunu duyurur. ──────
            Builder(
              builder: (context) {
                final couch = ref.watch(couchProvider);
                final invite = couch.hasPendingInvite ? couch.session : null;
                return _liveCard(
                  c: c,
                  tr: tr,
                  inviteFrom: invite?.friendName,
                  onTap: () => _push(const CouchScreen()),
                );
              },
            ),
            const SizedBox(height: 12),

            // ── Bento: iki kompakt eşleştirme modu ────────────────────────
            Row(
              children: [
                Expanded(
                  child: _gridCard(
                    c: c,
                    title:
                        tr?.get('together_friend_match_title') ??
                        'Friend Match',
                    subtitle:
                        tr?.get('together_friend_match_desc') ??
                        'Live, shared code',
                    icon: Icons.group_add_rounded,
                    accent: c.red,
                    onTap: () => _push(
                      const MatchScreen(initialMode: 2, hideModeSelector: true),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _gridCard(
                    c: c,
                    title: tr?.get('together_couch_title') ?? 'Couch Mode',
                    subtitle: tr?.get('together_couch_desc') ?? 'On one phone',
                    icon: Icons.people_rounded,
                    accent: c.gold,
                    onTap: () => _push(
                      const MatchScreen(initialMode: 1, hideModeSelector: true),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Birlikte Seç" canlı oturum kartı: crimson vurgulu, CANLI rozetli.
  /// Bekleyen davet varsa alt metin davetle değişir ve nabız noktası yanar.
  Widget _liveCard({
    required ThemePalette c,
    required AppLocalizations? tr,
    String? inviteFrom,
    required VoidCallback onTap,
  }) {
    final subtitle = inviteFrom != null
        ? (tr?.get('couch_invite_waiting').replaceAll('{}', inviteFrom) ??
              '$inviteFrom seni bekliyor!')
        : (tr?.get('couch_live_subtitle') ?? 'Canlı: iki telefon, tek karar');
    return SpringButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: c.crimson.withValues(alpha: inviteFrom != null ? 0.7 : 0.35),
            width: 1.5,
          ),
          boxShadow: CinemaShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.crimson.withValues(alpha: 0.14),
              ),
              alignment: Alignment.center,
              child: const Text('🍿', style: TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tr?.get('couch_live_title') ?? 'Birlikte Seç',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.crimson,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tr?.get('couch_live_badge') ?? 'CANLI',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: inviteFrom != null ? c.crimson : c.dim,
                      fontSize: 12,
                      fontWeight: inviteFrom != null
                          ? FontWeight.w700
                          : FontWeight.w400,
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
    );
  }

  /// Geniş "hero" kart — altın gradyanlı, en öne çıkan (Sosyal).
  Widget _heroCard({
    required ThemePalette c,
    required String title,
    required String subtitle,
    required IconData icon,
    required int badge,
    required VoidCallback onTap,
  }) {
    return SpringButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.gold.withValues(alpha: 0.35), width: 1.5),
          boxShadow: CinemaShadows.card,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.gold.withValues(alpha: 0.14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: c.gold, size: 28),
                ),
                if (badge > 0)
                  Positioned(right: -4, top: -4, child: _badgePill(c, badge)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: c.dim, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.dim, size: 24),
          ],
        ),
      ),
    );
  }

  /// Kompakt bento kart (2'li grid).
  Widget _gridCard({
    required ThemePalette c,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return SpringButton(
      onTap: onTap,
      child: Container(
        height: 132,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 20),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: c.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: c.dim, fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgePill(ThemePalette c, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: c.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.bg, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
