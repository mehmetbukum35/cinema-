import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entrance.dart';
import '../../widgets/spring_button.dart';
import '../login_screen.dart';
import '../together_screen.dart';
import 'browse_section_header.dart';

/// Misafir Keşfet: arkadaş akışı yokken sosyal özelliğin varlığını gösteren
/// tek satırlık teaser — sahte feed üretmez.
class BrowseFriendsActivityTeaser extends StatelessWidget {
  const BrowseFriendsActivityTeaser({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  tr?.get('browse_friends_activity') ??
                  'Arkadaşlarından Son Sinyaller',
              gradient: CinemaGradients.crimson,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr?.get('browse_friends_teaser_body') ??
                          'Friends’ ratings and picks show up here. Sign in to connect — or open Together to see how it works.',
                      style: TextStyle(
                        color: c.ink.withValues(alpha: 0.85),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SpringButton(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: c.crimson,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tr?.get('auth_title_login') ?? 'Sign In',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TogetherScreen(),
                              ),
                            );
                          },
                          child: Text(
                            tr?.get('browse_friends_teaser_together') ??
                                'Open Together',
                            style: TextStyle(
                              color: c.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
