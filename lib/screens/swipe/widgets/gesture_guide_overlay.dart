import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/localization_service.dart';
import '../../../services/prefs_service.dart';
import '../../../theme/app_theme.dart';

/// İlk kullanımda gösterilen swipe jest rehberi katmanı.
class SwipeGestureGuideOverlay extends StatelessWidget {
  final ThemePalette palette;
  final VoidCallback onDismiss;

  const SwipeGestureGuideOverlay({
    super.key,
    required this.palette,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.red.withValues(alpha: 0.15),
                    border: Border.all(
                      color: c.red.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(Icons.swipe_rounded, color: c.red, size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)?.get('discovery_gestures') ??
                      'Discovery Gestures',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.get('swipe_cards_to_train_our_recom') ??
                      'Swipe cards to train our recommendation engine!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 40),
                _GuideRow(
                  icon: Icons.arrow_forward_rounded,
                  color: c.green,
                  title:
                      AppLocalizations.of(context)?.get('swipe_right') ??
                      'Swipe Right',
                  subtitle:
                      AppLocalizations.of(
                        context,
                      )?.get('liked_good_or_amazing') ??
                      'Liked (Good or Amazing)',
                ),
                const SizedBox(height: 20),
                _GuideRow(
                  icon: Icons.arrow_back_rounded,
                  color: c.red,
                  title:
                      AppLocalizations.of(context)?.get('swipe_left') ??
                      'Swipe Left',
                  subtitle:
                      AppLocalizations.of(
                        context,
                      )?.get('disliked_meh_or_awful') ??
                      'Disliked (Meh or Awful)',
                ),
                const SizedBox(height: 20),
                _GuideRow(
                  icon: Icons.touch_app_rounded,
                  color: c.gold,
                  title:
                      AppLocalizations.of(context)?.get('tap_card') ??
                      'Tap Card',
                  subtitle:
                      AppLocalizations.of(
                        context,
                      )?.get('view_details_trailer_cast') ??
                      'View Details, Trailer & Cast',
                ),
                const SizedBox(height: 50),
                ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await PrefsService.setSwipeGuideShown();
                    onDismiss();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    shadowColor: c.red.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.get('got_it_lets_start') ??
                        'Got it, Let\'s Start!',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _GuideRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
