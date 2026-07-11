import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/share_helper.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'social/activity_card.dart';
import 'social/friend_list_tile.dart';
import 'social/profile_settings_sheet.dart';
import 'social/recommendation_card.dart';
import 'social/top_profile_card.dart';

export 'social/friend_activity_screen.dart' show FriendActivityScreen;

/// Sosyal ağ orkestratörü: sekmeler, arkadaşlık işlemleri ve sonuç
/// bildirimleri burada; kartlar ve alt sayfalar social/ altında yaşar.
class SocialScreen extends ConsumerStatefulWidget {
  /// Açılışta seçili olacak sekme (0: Arkadaşlar, 1: İstekler, 2: Akış).
  /// Bildirimden açıldığında İstekler sekmesine yönlendirmek için kullanılır.
  final int initialTab;
  const SocialScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  bool _isPublic = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    // Akış sekmesi açıldığında gelen önerileri "görüldü" işaretle.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        ref.read(socialProvider.notifier).markRecommendationsSeen();
      }
    });
    // Menüden/bildirimden doğrudan Akış ile açıldıysa listener tetiklenmez;
    // görüldü işaretini burada ver.
    if (widget.initialTab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(socialProvider.notifier).markRecommendationsSeen();
        }
      });
    }

    // Initial data load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socialProvider.notifier).loadFriends();
      ref.read(socialProvider.notifier).loadActivityFeed();
      ref.read(socialProvider.notifier).loadRecommendations();
      ref.read(socialProvider.notifier).loadTopProfiles();

      final auth = ref.read(authProvider);
      if (auth.user != null) {
        setState(() {
          _usernameCtrl.text = auth.user!['username'] ?? '';
          _isPublic = (auth.user!['is_public'] ?? 1) == 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendFriendRequest() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    final success = await ref
        .read(socialProvider.notifier)
        .sendFriendRequest(query);
    if (success && mounted) _searchCtrl.clear();
    _showSocialResult(
      success,
      'friend_request_sent',
      'Arkadaşlık isteği gönderildi. Karşı taraf onaylayınca arkadaş olacaksınız.',
    );
  }

  /// Sosyal işlemin sonucunu görünür kılar: başarıda [okKey] mesajı, hatada
  /// sunucunun döndüğü mesaj (varsa) gösterilir. Bu işlemler daha önce
  /// sessizdi — kullanıcı işlemin yapılıp yapılmadığını bilemiyordu.
  void _showSocialResult(bool ok, String okKey, String okFallback) {
    if (!mounted) return;
    final tr = AppLocalizations.of(context);
    if (ok) {
      showAppToast(context, tr?.get(okKey) ?? okFallback);
    } else {
      final err = ref.read(socialProvider).error;
      showAppToast(
        context,
        err ?? (tr?.get('auth_err_generic') ?? 'Bir hata oluştu.'),
        success: false,
      );
    }
  }

  Future<void> _acceptRequest(int friendId) async {
    final ok = await ref.read(socialProvider.notifier).acceptRequest(friendId);
    _showSocialResult(
      ok,
      'friend_request_accepted',
      'Arkadaşlık isteği kabul edildi. Artık arkadaşsınız.',
    );
  }

  Future<void> _declineRequest(int friendId) async {
    final ok = await ref.read(socialProvider.notifier).rejectRequest(friendId);
    _showSocialResult(ok, 'friend_request_declined', 'İstek silindi.');
  }

  Future<void> _withdrawRequest(int friendId) async {
    final ok = await ref.read(socialProvider.notifier).rejectRequest(friendId);
    _showSocialResult(ok, 'friend_request_withdrawn', 'İstek geri çekildi.');
  }

  Future<void> _removeFriend(int friendId) async {
    final ok = await ref.read(socialProvider.notifier).rejectRequest(friendId);
    _showSocialResult(ok, 'friend_removed', 'Arkadaşlıktan çıkarıldı.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final socialState = ref.watch(socialProvider);
    final authUser = ref.watch(authProvider).user;

    final tr = AppLocalizations.of(context);
    final isTr = tr?.locale.languageCode == 'tr';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.navBg,
        elevation: 0,
        title: Text(
          AppLocalizations.of(context)?.get('social_network') ??
              'Social Network',
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (authUser != null && authUser['username'] != null)
            Builder(
              builder: (shareBtnContext) => IconButton(
                icon: Icon(Icons.share_rounded, color: c.gold),
                onPressed: () {
                  final username = authUser['username'];
                  final profileUrl = ApiService.webProfileUrl(
                    username,
                    lang: isTr ? 'tr' : 'en',
                  );
                  final tr = AppLocalizations.of(context);
                  shareMessage(
                    context: context,
                    anchorContext: shareBtnContext,
                    message:
                        tr
                            ?.get('share_profile_text')
                            .replaceAll('{}', profileUrl) ??
                        'Follow me on What to Watch! Check out my watchlist and favorites here: $profileUrl',
                    failureMessage:
                        tr?.get('profile_share_failed') ??
                        'Paylaşım açılamadı. Lütfen tekrar deneyin.',
                  );
                },
              ),
            ),
          IconButton(
            icon: Icon(Icons.settings_rounded, color: c.dim),
            onPressed: () => _openProfileSettingsSheet(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: c.gold,
          labelColor: c.ink,
          unselectedLabelColor: c.dim,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              text:
                  AppLocalizations.of(context)?.get('together_friends') ??
                  'Friends',
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.get('requests') ??
                          'Requests',
                    ),
                    if (socialState.pendingReceived.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _tabBadge(
                        socialState.pendingReceived.length.toString(),
                        background: c.red,
                        foreground: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.get('activity') ??
                          'Activity',
                    ),
                    if (socialState.unseenRecommendations > 0) ...[
                      const SizedBox(width: 6),
                      _tabBadge(
                        socialState.unseenRecommendations.toString(),
                        background: c.gold,
                        foreground: Colors.black,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Tab(
              text: AppLocalizations.of(context)?.get('top_lists') ?? 'Popular',
            ),
          ],
        ),
      ),
      body: authUser == null || authUser['username'] == null
          ? _buildProfileSetupPlaceholder(c)
          : (socialState.loading &&
                    socialState.friends.isEmpty &&
                    socialState.activityFeed.isEmpty
                ? Center(child: CircularProgressIndicator(color: c.gold))
                : Column(
                    children: [
                      if (socialState.error != null)
                        Container(
                          width: double.infinity,
                          color: c.red.withValues(alpha: 0.15),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          child: Text(
                            socialState.error!,
                            style: TextStyle(
                              color: c.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildFriendsTab(c, socialState, isTr),
                            _buildRequestsTab(c, socialState, isTr),
                            _buildActivityTab(c, socialState, isTr),
                            _buildTopListsTab(c, socialState, isTr),
                          ],
                        ),
                      ),
                    ],
                  )),
    );
  }

  /// Sekme başlığındaki sayaç rozeti (istek/öneri).
  Widget _tabBadge(
    String text, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _openProfileSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProfileSettingsSheet(
        usernameCtrl: _usernameCtrl,
        isPublic: _isPublic,
        onPublicChanged: (val) => setState(() => _isPublic = val),
      ),
    );
  }

  Widget _buildProfileSetupPlaceholder(ThemePalette c) {
    final tr = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.people_alt_rounded, color: c.gold, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              tr?.get('customize_profile') ?? 'Customize Profile',
              style: TextStyle(
                color: c.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr?.get('social_customize_desc') ??
                  'Choose a username to add friends and see your cinema harmony.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _openProfileSettingsSheet(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              child: Text(
                tr?.get('social_set_username') ?? 'Set Username',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsTab(ThemePalette c, SocialState state, bool isTr) {
    return Column(
      children: [
        // Search & Add Friend Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(color: c.ink),
                    decoration: InputDecoration(
                      hintText:
                          AppLocalizations.of(
                            context,
                          )?.get('username_or_email') ??
                          'Username or email...',
                      hintStyle: TextStyle(color: c.dim),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sendFriendRequest,
                style: IconButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.person_add_rounded),
              ),
            ],
          ),
        ),

        Expanded(
          child: state.friends.isEmpty
              ? Center(
                  child: Text(
                    AppLocalizations.of(context)?.get('no_friends_added_yet') ??
                        'No friends added yet.',
                    style: TextStyle(color: c.dim),
                  ),
                )
              : ListView.builder(
                  itemCount: state.friends.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, idx) {
                    final f = state.friends[idx];
                    return FriendListTile(
                      friend: f,
                      tasteScore: state.tasteScores[f.id],
                      onRemove: () => _removeFriend(f.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRequestsTab(ThemePalette c, SocialState state, bool isTr) {
    if (state.pendingReceived.isEmpty && state.pendingSent.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('no_pending_requests') ??
              'No pending requests.',
          style: TextStyle(color: c.dim),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.pendingReceived.isNotEmpty) ...[
          Text(
            AppLocalizations.of(context)?.get('received_requests') ??
                'Received Requests',
            style: TextStyle(
              color: c.gold,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...state.pendingReceived.map((f) {
            final name = f.displayName ?? f.username;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.borderSoft),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: c.border,
                    foregroundColor: c.ink,
                    child: Text(name[0].toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                    onPressed: () => _acceptRequest(f.id),
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel_rounded, color: c.red),
                    onPressed: () => _declineRequest(f.id),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
        ],

        if (state.pendingSent.isNotEmpty) ...[
          Text(
            AppLocalizations.of(context)?.get('sent_requests') ??
                'Sent Requests',
            style: TextStyle(
              color: c.dim,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...state.pendingSent.map((f) {
            final name = f.displayName ?? f.username;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.borderSoft),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: c.borderSoft,
                    foregroundColor: c.dim,
                    child: Text(name[0].toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: c.dim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)?.get('pending') ?? 'Pending',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: c.red.withValues(alpha: 0.6),
                    ),
                    onPressed: () => _withdrawRequest(f.id),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildActivityTab(ThemePalette c, SocialState state, bool isTr) {
    if (state.activityFeed.isEmpty && state.recommendations.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.get('no_friend_activity_yet') ??
              'No friend activity yet.',
          style: TextStyle(color: c.dim),
        ),
      );
    }

    // Gelen öneriler akışın en üstünde gösterilir (varsa +1 başlık satırı).
    final recCount = state.recommendations.isEmpty
        ? 0
        : state.recommendations.length + 1;

    return ListView.builder(
      itemCount: recCount + state.activityFeed.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, idx) {
        if (recCount > 0 && idx == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              AppLocalizations.of(context)?.get('recommended_to_you') ??
                  'Recommended to You',
              style: TextStyle(
                color: c.gold,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        if (recCount > 0 && idx < recCount) {
          return RecommendationInboxCard(
            rec: state.recommendations[idx - 1],
            isLast: idx == recCount - 1,
          );
        }
        return ActivityCard(act: state.activityFeed[idx - recCount]);
      },
    );
  }

  // ─── Popüler Listeler sekmesi ─────────────────────────────────────────────
  Widget _buildTopListsTab(ThemePalette c, SocialState state, bool isTr) {
    if (state.topProfilesLoading && state.topProfiles.isEmpty) {
      return Center(child: CircularProgressIndicator(color: c.gold));
    }
    if (state.topProfiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AppLocalizations.of(context)?.get('top_lists_empty') ??
                'No public profiles yet.',
            style: TextStyle(color: c.dim),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: c.gold,
      onRefresh: () => ref.read(socialProvider.notifier).loadTopProfiles(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: state.topProfiles.length,
        itemBuilder: (context, idx) =>
            TopProfileCard(profile: state.topProfiles[idx], rank: idx + 1),
      ),
    );
  }
}
