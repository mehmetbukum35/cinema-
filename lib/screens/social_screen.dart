import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/pulsing_placeholder.dart';
import 'movie_detail/spoiler_comment.dart';
import '../models/movie.dart';
import 'movie_detail_sheet.dart';
import '../services/providers.dart';

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
  bool _showProfileSetup = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    // Akış sekmesi açıldığında gelen önerileri "görüldü" işaretle.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        ref.read(socialProvider.notifier).markRecommendationsSeen();
      }
    });

    // Initial data load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socialProvider.notifier).loadFriends();
      ref.read(socialProvider.notifier).loadActivityFeed();
      ref.read(socialProvider.notifier).loadRecommendations();

      final auth = ref.read(authProvider);
      if (auth.user != null) {
        setState(() {
          _usernameCtrl.text = auth.user!['username'] ?? '';
          _isPublic = (auth.user!['is_public'] ?? 1) == 1;
          _showProfileSetup = (auth.user!['username'] == null);
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

  Future<void> _setupProfile() async {
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.get('please_enter_a_username') ??
                'Please enter a username.',
          ),
        ),
      );
      return;
    }

    final success = await ref
        .read(socialProvider.notifier)
        .setupProfile(username, _isPublic);
    if (success && mounted) {
      setState(() => _showProfileSetup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.get('profile_updated_successfully') ??
                'Profile updated successfully.',
          ),
        ),
      );
    }
  }

  Future<void> _sendFriendRequest() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    final success = await ref
        .read(socialProvider.notifier)
        .sendFriendRequest(query);
    if (success && mounted) {
      _searchCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.get('friend_request_sent') ??
                'Friend request sent.',
          ),
        ),
      );
    }
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
            IconButton(
              icon: Icon(Icons.share_rounded, color: c.gold),
              onPressed: () {
                final username = authUser['username'];
                Share.share(
                  AppLocalizations.of(context)
                          ?.get('share_profile_text')
                          .replaceAll(
                            '{}',
                            '${ApiService.webProfileBaseUrl}/$username',
                          ) ??
                      'Follow me on What to Watch! Check out my watchlist and favorites here: ${ApiService.webProfileBaseUrl}/$username',
                );
              },
            ),
          IconButton(
            icon: Icon(Icons.settings_rounded, color: c.dim),
            onPressed: () =>
                setState(() => _showProfileSetup = !_showProfileSetup),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('requests') ?? 'Requests',
                  ),
                  if (socialState.pendingReceived.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        socialState.pendingReceived.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)?.get('activity') ?? 'Activity',
                  ),
                  if (socialState.unseenRecommendations > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.gold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        socialState.unseenRecommendations.toString(),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body:
          socialState.loading &&
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

                if (_showProfileSetup) _buildProfileSetupPanel(c, isTr),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsTab(c, socialState, isTr),
                      _buildRequestsTab(c, socialState, isTr),
                      _buildActivityTab(c, socialState, isTr),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileSetupPanel(ThemePalette c, bool isTr) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context)?.get('customize_profile') ??
                'Customize Profile',
            style: TextStyle(
              color: c.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameCtrl,
            style: TextStyle(color: c.ink),
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context)?.get('username_username') ??
                  'Username (@username)',
              labelStyle: TextStyle(color: c.dim),
              prefixText: '@',
              prefixStyle: TextStyle(
                color: c.gold,
                fontWeight: FontWeight.w700,
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.gold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: Text(
              AppLocalizations.of(context)?.get('public_profile') ??
                  'Public Profile',
              style: TextStyle(color: c.ink, fontSize: 14),
            ),
            subtitle: Text(
              AppLocalizations.of(
                    context,
                  )?.get('when_disabled_your_profile_can') ??
                  'When disabled, your profile cannot be viewed on the web.',
              style: TextStyle(color: c.dim, fontSize: 11),
            ),
            value: _isPublic,
            activeThumbColor: c.gold,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _isPublic = val),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _setupProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)?.get('save_settings') ??
                  'Save Settings',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
                    final name = f['display_name'] ?? f['username'] ?? 'User';
                    final handle = f['username'] ?? '';
                    final friendId = int.tryParse(f['id'].toString()) ?? 0;
                    final tasteScore = state.tasteScores[friendId];

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FriendActivityScreen(
                              friendId: friendId,
                              friendName: name,
                              friendUsername: handle,
                              tasteScore: tasteScore,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.borderSoft),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: CinemaGradients.crimson,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: c.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (handle.isNotEmpty)
                                    Text(
                                      '@$handle',
                                      style: TextStyle(
                                        color: c.dim,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (tasteScore != null) ...[
                                    const SizedBox(height: 6),
                                    // Zevk uyumu rozeti (0-100)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.gold.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: c.gold.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.favorite_rounded,
                                            color: c.gold,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            AppLocalizations.of(context)
                                                    ?.get('taste_score_match')
                                                    .replaceAll(
                                                      '{}',
                                                      '$tasteScore',
                                                    ) ??
                                                '$tasteScore% match',
                                            style: TextStyle(
                                              color: c.gold,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.person_remove_rounded,
                                color: c.red.withValues(alpha: 0.7),
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: c.surface,
                                    title: Text(
                                      AppLocalizations.of(
                                            context,
                                          )?.get('remove_friend') ??
                                          'Remove Friend',
                                    ),
                                    content: Text(
                                      AppLocalizations.of(context)
                                              ?.get('remove_friend_confirm_msg')
                                              .replaceAll('{}', name) ??
                                          'Are you sure you want to remove $name from friends?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.get('profile_cancel') ??
                                              'Cancel',
                                          style: TextStyle(color: c.dim),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          final id =
                                              int.tryParse(
                                                f['id'].toString(),
                                              ) ??
                                              0;
                                          await ref
                                              .read(socialProvider.notifier)
                                              .rejectRequest(id);
                                        },
                                        child: Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.get('remove') ??
                                              'Remove',
                                          style: TextStyle(color: c.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
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
            final name = f['display_name'] ?? f['username'] ?? 'User';
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
                    onPressed: () {
                      final id = int.tryParse(f['id'].toString()) ?? 0;
                      ref.read(socialProvider.notifier).acceptRequest(id);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel_rounded, color: c.red),
                    onPressed: () {
                      final id = int.tryParse(f['id'].toString()) ?? 0;
                      ref.read(socialProvider.notifier).rejectRequest(id);
                    },
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
            final name = f['display_name'] ?? f['username'] ?? 'User';
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
                    onPressed: () {
                      final id = int.tryParse(f['id'].toString()) ?? 0;
                      ref.read(socialProvider.notifier).rejectRequest(id);
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Gelen tek bir öneri kartı (gönderen + yapım + varsa not).
  Widget _buildRecommendationCard(
    ThemePalette c,
    dynamic rec,
    bool isTr, {
    bool isLast = false,
  }) {
    final fromName = rec['from_name'] ?? rec['from_username'] ?? 'Friend';
    final title = rec['title'] ?? 'Movie';
    final note = (rec['note'] ?? '').toString();
    final posterPath = rec['poster_path'];
    final isTv = _parseIsTv(rec);
    final seen = rec['seen'] == true;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final movieId = _parseMovieId(rec);
        if (movieId > 0) {
          _openMovieDetail(context, ref, movieId, isTv);
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 24 : 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: seen ? c.borderSoft : c.gold.withValues(alpha: 0.5),
          ),
          boxShadow: CinemaShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60,
                height: 90,
                child: posterPath != null
                    ? CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w200$posterPath',
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const PulsingPlaceholder(),
                        errorWidget: (context, url, error) => Container(
                          color: c.border,
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_rounded, color: c.dim),
                        ),
                      )
                    : Container(
                        color: c.border,
                        alignment: Alignment.center,
                        child: Icon(Icons.movie_rounded, color: c.dim),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.card_giftcard_rounded,
                        color: c.gold,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)
                                  ?.get('recommended_by_user')
                                  .replaceAll('{}', fromName) ??
                              'Recommended by $fromName',
                          style: TextStyle(
                            color: c.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isTv
                        ? (AppLocalizations.of(context)?.get('onboarding_tv') ??
                              'TV Show')
                        : (AppLocalizations.of(
                                context,
                              )?.get('onboarding_movie') ??
                              'Movie'),
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '"$note"',
                      style: TextStyle(
                        color: c.dim,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
          return _buildRecommendationCard(
            c,
            state.recommendations[idx - 1],
            isTr,
            isLast: idx == recCount - 1,
          );
        }
        final act = state.activityFeed[idx - recCount];
        return FriendActivityScreen._buildActivityCard(c, act, context, ref);
      },
    );
  }
}

class FriendActivityScreen extends ConsumerStatefulWidget {
  final int friendId;
  final String friendName;
  final String friendUsername;
  final int? tasteScore;

  const FriendActivityScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.friendUsername,
    this.tasteScore,
  });

  @override
  ConsumerState<FriendActivityScreen> createState() =>
      _FriendActivityScreenState();

  static Widget _buildActivityCard(
    ThemePalette c,
    Map<String, dynamic> act,
    BuildContext context,
    WidgetRef ref,
  ) {
    final friendName = act['friend_name'] ?? act['friend_username'] ?? 'Friend';
    final title = act['title'] ?? 'Movie';
    final ratingVal = act['rating'] is int
        ? act['rating'] as int
        : (int.tryParse(act['rating']?.toString() ?? '') ?? 3);
    final posterPath = act['poster_path'];
    final isTv = _parseIsTv(act);
    final comment = act['comment'] as String?;
    final isSpoiler = (act['is_spoiler'] ?? 0) == 1;

    Color badgeColor = c.rIyi;
    String badgeText = 'İyi';
    if (ratingVal == 3) {
      badgeColor = c.rHarika;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_amazing') ?? 'Amazing';
    } else if (ratingVal == 2) {
      badgeColor = c.rIyi;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_good') ?? 'Good';
    } else if (ratingVal == 1) {
      badgeColor = c.rEh;
      badgeText = AppLocalizations.of(context)?.get('recap_stat_meh') ?? 'Meh';
    } else if (ratingVal == 0) {
      badgeColor = c.rBerbat;
      badgeText =
          AppLocalizations.of(context)?.get('recap_stat_awful') ?? 'Awful';
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final movieId = _parseMovieId(act);
        if (movieId > 0) {
          _openMovieDetail(context, ref, movieId, isTv);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.borderSoft),
          boxShadow: CinemaShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60,
                height: 90,
                child: posterPath != null
                    ? CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w200$posterPath',
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const PulsingPlaceholder(),
                        errorWidget: (context, url, error) => Container(
                          color: c.border,
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_rounded, color: c.dim),
                        ),
                      )
                    : Container(
                        color: c.border,
                        alignment: Alignment.center,
                        child: Icon(Icons.movie_rounded, color: c.dim),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.border,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          friendName[0].toUpperCase(),
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          friendName,
                          style: TextStyle(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isTv
                        ? (AppLocalizations.of(context)?.get('onboarding_tv') ??
                              'TV Show')
                        : (AppLocalizations.of(
                                context,
                              )?.get('onboarding_movie') ??
                              'Movie'),
                    style: TextStyle(
                      color: c.dim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: badgeColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (comment != null && comment.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SpoilerComment(comment: comment, isSpoiler: isSpoiler),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendActivityScreenState extends ConsumerState<FriendActivityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(socialProvider.notifier).loadFriendActivity(widget.friendId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final socialState = ref.watch(socialProvider);

    final friendActivities =
        socialState.friendActivities[widget.friendId] ?? [];
    final isLoading = socialState.loading && friendActivities.isEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.friendName,
              style: TextStyle(
                color: c.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '@${widget.friendUsername}',
              style: TextStyle(color: c.dim, fontSize: 12),
            ),
          ],
        ),
      ),
      body: CinematicBackground(
        child: Column(
          children: [
            if (widget.tasteScore != null) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.borderSoft),
                  boxShadow: CinemaShadows.card,
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
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.favorite_rounded,
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
                            AppLocalizations.of(
                                  context,
                                )?.get('cinema_taste_match') ??
                                'Cinema Taste Match',
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            AppLocalizations.of(context)
                                    ?.get('friend_taste_match_desc')
                                    .replaceAll('{}', '${widget.tasteScore}') ??
                                'You have a ${widget.tasteScore}% movie taste match with this friend.',
                            style: TextStyle(
                              color: c.dim,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '%${widget.tasteScore}',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: isLoading
                  ? Center(child: CircularProgressIndicator(color: c.gold))
                  : friendActivities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c.dim.withValues(alpha: 0.1),
                            ),
                            child: Icon(
                              Icons.history_rounded,
                              color: c.dim,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.get('no_activity_from_this_friend_y') ??
                                'No activity from this friend yet.',
                            style: TextStyle(color: c.dim, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: friendActivities.length,
                      itemBuilder: (ctx, i) {
                        return FriendActivityScreen._buildActivityCard(
                          c,
                          friendActivities[i],
                          ctx,
                          ref,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
bool _parseIsTv(dynamic data) {
  if (data == null) return false;
  final val = data['is_tv'] ?? data['isTV'] ?? data['isTv'];
  return val == true ||
      val == 1 ||
      val?.toString() == '1' ||
      val?.toString() == 'true';
}

int _parseMovieId(dynamic data) {
  if (data == null) return 0;
  final val = data['movie_id'] ?? data['id'] ?? data['movieId'];
  return int.tryParse(val?.toString() ?? '') ?? 0;
}

Future<void> _openMovieDetail(
  BuildContext context,
  WidgetRef ref,
  int movieId,
  bool isTv,
) async {
  final service = ref.read(tmdbServiceProvider);
  final c = context.c;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) =>
        Center(child: CircularProgressIndicator(color: c.gold)),
  );

  try {
    final details = await service.getFullDetails(movieId, isTV: isTv);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yapım detayları yüklenemedi.')),
        );
      }
      return;
    }

    if (context.mounted) {
      final movie = Movie.fromJson(details, isTV: isTv);
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => MovieDetailSheet(movie: movie, service: service),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }
}
