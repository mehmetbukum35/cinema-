import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social.dart';
import '../providers/auth_provider.dart';
import '../providers/couch_provider.dart';
import '../providers/social_provider.dart';
import '../services/localization_service.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_cached_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/spring_button.dart';
import 'login_screen.dart';
import 'movie_detail_sheet.dart';
import 'social_screen.dart';

/// "Birlikte Seç" — canlı kanepe modu. İki arkadaş kendi telefonlarından aynı
/// desteyi oylar; ilk karşılıklı beğeni kazanır. Ekran, oturumun yaşam
/// döngüsünü (arkadaş seç → oyla → eşleşme/bitiş) tek akışta sunar; canlılık
/// couchProvider'ın kısa aralıklı poll'uyla sağlanır.
class CouchScreen extends ConsumerStatefulWidget {
  const CouchScreen({super.key});

  @override
  ConsumerState<CouchScreen> createState() => _CouchScreenState();
}

class _CouchScreenState extends ConsumerState<CouchScreen>
    with SingleTickerProviderStateMixin {
  // dispose() içinde ref KULLANILAMAZ ("Cannot use ref after the widget was
  // disposed"); notifier referansı initState'te alınır, dispose ref'siz çalışır.
  late final CouchNotifier _couch;
  AnimationController? _theirProgressAnimController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _couch = ref.read(couchProvider.notifier);

    _theirProgressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 50),
        ]).animate(
          CurvedAnimation(
            parent: _theirProgressAnimController!,
            curve: Curves.easeInOut,
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _couch.checkActive();
      _couch.startPolling();
      if (ref.read(socialProvider).friends.isEmpty) {
        ref.read(socialProvider.notifier).loadFriends();
      }
    });
  }

  @override
  void dispose() {
    _theirProgressAnimController?.dispose();
    // Poll yalnızca bu ekran açıkken çalışır (pil/istek tasarrufu).
    _couch.stopPolling();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(
          tr?.get('couch_leave') ?? 'Oturumdan çık',
          style: TextStyle(color: c.ink, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              tr?.get('profile_cancel') ?? 'İptal',
              style: TextStyle(color: c.dim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr?.get('couch_leave') ?? 'Çık',
              style: TextStyle(color: c.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      await ref.read(couchProvider.notifier).leave();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);

    // Hatalar (oturum kurulamadı, sunucu güncel değil…) sessizce yutulmasın:
    // kullanıcı "hiçbir şey olmadı" sanıyordu. l10n anahtarıysa çevir.
    ref.listen<CouchState>(couchProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        final msg = switch (err) {
          'couch_server_outdated' =>
            tr?.get('couch_server_outdated') ??
                'Sunucu bu özelliği henüz tanımıyor. Backend güncellemesi gerekli.',
          'couch_session_closed' =>
            tr?.get('couch_session_closed') ?? 'Oturum kapandı.',
          _ => err,
        };
        showAppToast(context, msg, success: false);
      }

      // Arkadaşın oylama ilerlemesi arttıysa animasyon tetikle, ses çal ve hafif haptic ver.
      final prevProgress = prev?.session?.theirProgress ?? 0;
      final nextProgress = next.session?.theirProgress ?? 0;
      if (nextProgress > prevProgress && next.session?.status == 'active') {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
        _theirProgressAnimController?.forward(from: 0.0);
      }
    });

    final couch = ref.watch(couchProvider);
    final session = couch.session;

    Widget body;
    if (!auth.isAuthenticated) {
      body = _CenteredMessage(
        icon: Icons.lock_outline_rounded,
        title: tr?.get('couch_login_required') ?? 'Giriş yapmalısın.',
        actionLabel: tr?.get('auth_title_login') ?? 'Giriş Yap',
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      );
    } else if (couch.loading) {
      body = _BuildingDeckView(
        label: tr?.get('couch_building_deck') ?? 'Deste hazırlanıyor…',
      );
    } else if (session == null || session.status == 'cancelled') {
      body = _FriendPicker(
        onSelect: (friend) async {
          HapticFeedback.mediumImpact();
          await ref.read(couchProvider.notifier).start(friend);
        },
      );
    } else if (session.status == 'matched' && session.matched != null) {
      body = _MatchView(
        session: session,
        onClose: () async {
          await ref.read(couchProvider.notifier).leave();
          if (context.mounted) Navigator.pop(context);
        },
      );
    } else if (session.status == 'ended') {
      body = _EndedView(session: session);
    } else {
      body = _VotingView(session: session, scaleAnimation: _scaleAnimation);
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: c.ink),
        title: Text(
          tr?.get('couch_live_title') ?? 'Birlikte Seç',
          style: TextStyle(
            color: c.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (session != null && session.isOpen)
            IconButton(
              tooltip: tr?.get('couch_leave') ?? 'Oturumdan çık',
              onPressed: _confirmLeave,
              icon: Icon(Icons.close_rounded, color: c.dim),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

// ─── Arkadaş seçici ───────────────────────────────────────────────────────

class _FriendPicker extends ConsumerWidget {
  final Future<void> Function(Friend friend) onSelect;

  const _FriendPicker({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final friends = ref.watch(socialProvider).friends;

    if (friends.isEmpty) {
      return _CenteredMessage(
        icon: Icons.group_add_rounded,
        title: tr?.get('couch_no_friends') ?? 'Önce bir arkadaş eklemelisin.',
        actionLabel: tr?.get('together_social_title') ?? 'Sosyal',
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SocialScreen()),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('🍿', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 10),
        Text(
          tr?.get('couch_pick_friend') ?? 'Kiminle seçeceksin?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr?.get('couch_pick_friend_desc') ??
              'Arkadaşını seç; ikinize özel bir deste hazırlayalım.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        for (final f in friends)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SpringButton(
              onTap: () => onSelect(f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.borderSoft),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: c.crimson.withValues(alpha: 0.15),
                      child: Text(
                        (f.displayName ?? f.username).isNotEmpty
                            ? (f.displayName ?? f.username)[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: c.crimson,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f.displayName ?? '@${f.username}',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.play_arrow_rounded, color: c.crimson, size: 22),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Oylama görünümü ──────────────────────────────────────────────────────

class _VotingView extends ConsumerWidget {
  final CouchSession session;
  final Animation<double> scaleAnimation;

  const _VotingView({required this.session, required this.scaleAnimation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final card = session.nextCard;

    return Column(
      children: [
        // Durum şeridi: ilerlemeler + (pending ise) bekleme notu.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _progressChip(
                    c,
                    label: tr?.get('couch_you') ?? 'Sen',
                    progress: session.myProgress,
                    total: session.deck.length,
                    accent: c.crimson,
                  ),
                  const SizedBox(width: 10),
                  ScaleTransition(
                    scale: scaleAnimation,
                    child: _progressChip(
                      c,
                      label: session.friendName,
                      progress: session.theirProgress,
                      total: session.deck.length,
                      accent: c.gold,
                    ),
                  ),
                ],
              ),
              if (session.status == 'pending') ...[
                const SizedBox(height: 8),
                Text(
                  tr
                          ?.get('couch_waiting_friend')
                          .replaceAll('{}', session.friendName) ??
                      '${session.friendName} daveti henüz açmadı',
                  style: TextStyle(
                    color: c.dim,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: card == null
              ? _CenteredMessage(
                  icon: Icons.hourglass_top_rounded,
                  title: tr?.get('couch_deck_done_title') ?? 'Kartların bitti!',
                  subtitle:
                      tr
                          ?.get('couch_deck_done_desc')
                          .replaceAll('{}', session.friendName) ??
                      '${session.friendName} bitirince sonuç belli olacak.',
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AppCachedNetworkImage(
                                imageUrl: card.posterUrl,
                                fit: BoxFit.cover,
                                preset: AppImageCachePreset.poster,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (card != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _voteButton(
                  context,
                  ref,
                  liked: false,
                  icon: Icons.close_rounded,
                  color: c.rBerbat,
                  label: tr?.get('couch_skip') ?? 'Geç',
                ),
                const SizedBox(width: 28),
                _voteButton(
                  context,
                  ref,
                  liked: true,
                  icon: Icons.favorite_rounded,
                  color: c.rHarika,
                  label: tr?.get('couch_like') ?? 'Beğen',
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _progressChip(
    ThemePalette c, {
    required String label,
    required int progress,
    required int total,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label $progress/$total',
        style: TextStyle(
          color: c.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _voteButton(
    BuildContext context,
    WidgetRef ref, {
    required bool liked,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SpringButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(couchProvider.notifier).vote(liked);
        },
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 30),
        ),
      ),
    );
  }
}

// ─── Eşleşme kutlaması ────────────────────────────────────────────────────

class _MatchView extends ConsumerWidget {
  final CouchSession session;
  final Future<void> Function() onClose;

  const _MatchView({required this.session, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final movie = session.matched!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.gold.withValues(alpha: 0.25),
            c.crimson.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr?.get('couch_match_title') ?? 'Eşleşme! 🎬',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr
                        ?.get('couch_match_desc')
                        .replaceAll('{}', session.friendName) ??
                    '${session.friendName} ile anlaştınız. İyi seyirler!',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AppCachedNetworkImage(
                      imageUrl: movie.posterUrl,
                      fit: BoxFit.cover,
                      preset: AppImageCachePreset.poster,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                movie.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final service = ref.read(tmdbServiceProvider);
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) =>
                          MovieDetailSheet(movie: movie, service: service),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.crimson,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    tr?.get('couch_view_detail') ?? 'Detayına Bak',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => onClose(),
                child: Text(
                  tr?.get('couch_close') ?? 'Kapat',
                  style: TextStyle(color: c.dim, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Eşleşmesiz bitiş ─────────────────────────────────────────────────────

class _EndedView extends ConsumerWidget {
  final CouchSession session;

  const _EndedView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = AppLocalizations.of(context);
    return _CenteredMessage(
      icon: Icons.sentiment_dissatisfied_rounded,
      title: tr?.get('couch_no_match_title') ?? 'Eşleşme çıkmadı 😅',
      subtitle:
          tr?.get('couch_no_match_desc') ??
          'Zevkler çatıştı. Yeni bir desteyle tekrar deneyin.',
      actionLabel: tr?.get('couch_new_deck') ?? 'Yeni Deste',
      onAction: () {
        HapticFeedback.mediumImpact();
        // Aynı arkadaşla taze deste: yeni oturum eskisini sunucuda kapatır.
        ref
            .read(couchProvider.notifier)
            .start(
              Friend(
                id: session.friendId,
                username: session.friendName,
                displayName: session.friendName,
              ),
            );
      },
    );
  }
}

// ─── Ortak küçük görünümler ───────────────────────────────────────────────

class _BuildingDeckView extends StatelessWidget {
  final String label;

  const _BuildingDeckView({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍿', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.gold),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              color: c.dim,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.dim, size: 44),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.dim, fontSize: 13, height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.crimson,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
