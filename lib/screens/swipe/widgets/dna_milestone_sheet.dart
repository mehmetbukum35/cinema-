import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/localization_service.dart';
import '../../../services/prefs_service.dart';
import '../../../theme/app_theme.dart';
import '../../taste_dna_screen.dart';

/// 5/25/50. puanlamadan sonra BİR KEZ gösterilen DNA daveti.
///
/// Sinema DNA'sı uygulamanın en paylaşılabilir özelliği ama tek girişi Profil
/// sekmesindeki banner'dı — swipe döngüsünde yaşayan kullanıcı varlığını hiç
/// öğrenmiyordu. Bu sheet, DNA'yı tam da onu besleyen eylemin (puanlama)
/// içinde keşfettirir ve ölçülen isabet oranını ilk kez kullanıcıya söyler.
Future<void> maybeShowDnaMilestone(BuildContext context) async {
  final count = await PrefsService.getRatingCount();
  final threshold = await PrefsService.pendingDnaMilestone(count);
  if (threshold == null) return;

  // İsabet oranı: öneri telemetrisinden. DNA'daki accuracy ile aynı eşik
  // (>=8 gösterim) — küçük örneklemde yanıltıcı yüzde göstermeyiz.
  int? accuracyPercent;
  try {
    final telemetry = await PrefsService.getRecoTelemetry();
    var shown = 0;
    var liked = 0;
    for (final bucket in telemetry.values) {
      shown += bucket['shown'] ?? 0;
      liked += bucket['liked'] ?? 0;
    }
    if (shown >= 8) {
      accuracyPercent = (liked / shown * 100).round();
    }
  } catch (_) {
    // Oransız gösterilir.
  }

  if (!context.mounted) return;
  HapticFeedback.mediumImpact();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => DnaMilestoneSheet(
      threshold: threshold,
      ratingCount: count,
      accuracyPercent: accuracyPercent,
    ),
  );
  // Mark only after the sheet was actually presented (or dismissed).
  await PrefsService.markDnaMilestoneShown(threshold);
}

class DnaMilestoneSheet extends StatelessWidget {
  final int threshold;
  final int ratingCount;
  final int? accuracyPercent;

  const DnaMilestoneSheet({
    super.key,
    required this.threshold,
    required this.ratingCount,
    this.accuracyPercent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    final isFirst = threshold == PrefsService.dnaMilestones.first;

    final title = isFirst
        ? (tr?.get('dna_milestone_unlocked_title') ?? "Sinema DNA'n hazır!")
        : (tr?.get('dna_milestone_refined_title') ?? "DNA'n keskinleşti");
    final desc = isFirst
        ? (tr
                  ?.get('dna_milestone_unlocked_desc')
                  .replaceAll('{}', '$ratingCount') ??
              '$ratingCount yapım oyladın — zevk kimliğin ortaya çıktı: '
                  'arketipin, temaların, kör noktan…')
        : (tr
                  ?.get('dna_milestone_refined_desc')
                  .replaceAll('{}', '$ratingCount') ??
              '$ratingCount oylamaya ulaştın. Zevk profilin artık çok daha '
                  'isabetli.');

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.gold.withValues(alpha: 0.95),
              c.crimson.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.crimson.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧬', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (accuracyPercent != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tr
                              ?.get('dna_milestone_accuracy')
                              .replaceAll('{}', '$accuracyPercent') ??
                          'Önerilerimizin isabeti: %$accuracyPercent',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Semantics(
              button: true,
              label: tr?.get('dna_milestone_cta') ?? "DNA'nı Gör",
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TasteDnaScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: c.crimson,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    tr?.get('dna_milestone_cta') ?? "DNA'nı Gör",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: tr?.get('dna_milestone_later') ?? 'Daha sonra',
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  tr?.get('dna_milestone_later') ?? 'Daha sonra',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
