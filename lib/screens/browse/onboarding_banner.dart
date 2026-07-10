import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/prefs_service.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../onboarding_screen.dart';

/// Zevk anketi hatırlatma bandı: dokununca onboarding'e götürür,
/// kapatınca kalıcı olarak gizlenir ([onDismissed] üst ekranı günceller).
class OnboardingReminderBanner extends StatelessWidget {
  final VoidCallback onDismissed;
  const OnboardingReminderBanner({super.key, required this.onDismissed});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.gold.withValues(alpha: 0.12),
            c.goldSoft.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gold.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 40, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.gold.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: c.gold,
                      size: 20,
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
                              )?.get('personalize_recommendations') ??
                              'Personalize Recommendations',
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.get('complete_the_2minute_survey_fo') ??
                              'Complete the 2-minute survey for the best matching movies and shows!',
                          style: TextStyle(
                            color: c.dim,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(Icons.close_rounded, color: c.dim, size: 18),
              onPressed: () async {
                HapticFeedback.lightImpact();
                await PrefsService.dismissOnboardingBanner();
                onDismissed();
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              splashRadius: 16,
            ),
          ),
        ],
      ),
    );
  }
}
