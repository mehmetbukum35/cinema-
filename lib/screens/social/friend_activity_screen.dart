import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/social_provider.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cinematic_background.dart';
import 'activity_card.dart';

/// Tek bir arkadaşın aktivite geçmişi: zevk uyumu kartı + aktivite listesi.
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

    return CinematicBackground(
      child: Scaffold(
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
        body: Column(
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
                      itemCount:
                          friendActivities.length +
                          (socialState.friendActivityHasMore &&
                                  socialState.friendActivityFriendId ==
                                      widget.friendId
                              ? 1
                              : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= friendActivities.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: socialState.friendActivityLoadingMore
                                  ? CircularProgressIndicator(color: c.gold)
                                  : TextButton(
                                      onPressed: () => ref
                                          .read(socialProvider.notifier)
                                          .loadMoreFriendActivity(
                                            widget.friendId,
                                          ),
                                      child: Text(
                                        AppLocalizations.of(
                                              context,
                                            )?.get('load_more') ??
                                            'Load more',
                                      ),
                                    ),
                            ),
                          );
                        }
                        return ActivityCard(act: friendActivities[i]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
