import 'package:flutter/material.dart';

import '../../models/social.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entrance.dart';
import 'browse_section_header.dart';
import 'browse_top_profile_card.dart';

/// Keşfet: popüler profil listeleri yatay rayı.
class BrowseTopProfilesSection extends StatelessWidget {
  const BrowseTopProfilesSection({super.key, required this.profiles});

  final List<TopProfile> profiles;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  AppLocalizations.of(context)?.get('top_lists_title') ??
                  'Popüler Listeler',
              gradient: CinemaGradients.crimson,
            ),
            SizedBox(
              height: 136,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: profiles.length,
                itemBuilder: (ctx, i) =>
                    BrowseTopProfileCard(profile: profiles[i], rank: i + 1),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
