import 'package:flutter/material.dart';

import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entrance.dart';
import 'browse_section_header.dart';
import 'friend_signal_card.dart';
import '../../models/movie.dart';

/// Keşfet: arkadaş aktivite sinyalleri yatay rayı.
class BrowseFriendsActivitySection extends StatelessWidget {
  const BrowseFriendsActivitySection({
    super.key,
    required this.feed,
    required this.onOpen,
    required this.onBlocked,
  });

  final List<ActivityItem> feed;
  final void Function(Movie movie) onOpen;
  final void Function(Movie movie) onBlocked;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  AppLocalizations.of(
                    context,
                  )?.get('browse_friends_activity') ??
                  'Arkadaşlarından Son Sinyaller',
              gradient: CinemaGradients.crimson,
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: feed.length,
                itemBuilder: (ctx, i) => FriendSignalCard(
                  item: feed[i],
                  onOpen: onOpen,
                  onBlocked: onBlocked,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
