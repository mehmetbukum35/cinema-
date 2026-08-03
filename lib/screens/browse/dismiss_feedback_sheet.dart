import 'package:flutter/material.dart';

import '../../models/dismiss_feedback.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class DismissFeedbackSheet extends StatelessWidget {
  const DismissFeedbackSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final options = [
      (
        DismissFeedbackReason.notNow,
        Icons.schedule_rounded,
        tr?.get('dismiss_not_now') ?? 'Şu an havasında değilim',
      ),
      (
        DismissFeedbackReason.alreadyWatched,
        Icons.check_circle_outline_rounded,
        tr?.get('dismiss_already_watched') ?? 'Zaten izledim',
      ),
      (
        DismissFeedbackReason.tooLong,
        Icons.timelapse_rounded,
        tr?.get('dismiss_too_long') ?? 'Fazla uzun',
      ),
      (
        DismissFeedbackReason.wrongCulture,
        Icons.public_off_rounded,
        tr?.get('dismiss_wrong_culture') ?? 'Bu sinema kültürü bana göre değil',
      ),
      (
        DismissFeedbackReason.wrongGenre,
        Icons.category_outlined,
        tr?.get('dismiss_wrong_genre') ?? 'Bu tür bana göre değil',
      ),
      (
        DismissFeedbackReason.notInterested,
        Icons.hide_source_rounded,
        tr?.get('dismiss_not_interested') ?? 'Bu yapım ilgimi çekmedi',
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr?.get('dismiss_feedback_title') ?? 'Neden olmadı?',
              style: TextStyle(
                color: c.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tr?.get('dismiss_feedback_desc') ??
                  'Cevabın yalnızca daha iyi öneriler vermemize yardımcı olur.',
              style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            for (final (reason, icon, label) in options)
              Semantics(
                button: true,
                label: label,
                child: ListTile(
                  minTileHeight: 48,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: c.gold),
                  title: Text(
                    label,
                    style: TextStyle(color: c.ink, fontSize: 15),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.dim),
                  onTap: () => Navigator.pop(context, reason),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                tr?.get('dismiss_feedback_skip') ?? 'Cevap vermeden geç',
                style: TextStyle(color: c.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
