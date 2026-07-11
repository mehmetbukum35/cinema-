import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import '../results_screen.dart';

class Mood {
  final IconData icon;
  final String label;
  final String? genreStr;
  final double? minRating;
  final int? maxRuntime;
  final String? decade;
  final bool includeTv;

  const Mood({
    required this.icon,
    required this.label,
    this.genreStr,
    this.minRating,
    this.maxRuntime,
    this.decade,
    this.includeTv = true,
  });
}

// NOT: TMDB with_genres'te virgül VE, pipe VEYA anlamına gelir. Mood'lar
// niyet olarak VEYA'dır ("gerilim lazım" = gerilim VEYA korku); virgüllü hali
// kesişim sorguladığı için (üstüne vote_count/minRating filtreleri binince)
// çoğu zaman boş sayfa döndürüyordu.
const moods = [
  Mood(
    icon: Icons.sentiment_very_satisfied_rounded,
    label: 'mood_funny',
    genreStr: '35|10402',
    includeTv: false,
  ),
  Mood(
    icon: Icons.psychology_rounded,
    label: 'mood_thrill',
    genreStr: '53|27|9648',
    minRating: 7.0,
    includeTv: false,
  ),
  Mood(
    icon: Icons.sentiment_very_dissatisfied_rounded,
    label: 'mood_cry',
    genreStr: '18|10749',
    minRating: 7.5,
  ),
  Mood(
    icon: Icons.bolt_rounded,
    label: 'mood_action',
    genreStr: '28|12',
    includeTv: false,
  ),
  Mood(
    icon: Icons.spa_rounded,
    label: 'mood_light',
    genreStr: '35|16|10751',
    maxRuntime: 100,
    includeTv: false,
  ),
  Mood(
    icon: Icons.lightbulb_outline_rounded,
    label: 'mood_thought',
    genreStr: '18|9648|36',
    minRating: 7.5,
  ),
  Mood(
    icon: Icons.favorite_rounded,
    label: 'mood_romance',
    genreStr: '10749',
    includeTv: false,
  ),
  Mood(
    icon: Icons.movie_filter_rounded,
    label: 'mood_classic',
    decade: '1990',
    minRating: 7.0,
    includeTv: false,
  ),
  Mood(
    icon: Icons.nights_stay_rounded,
    label: 'mood_scary',
    genreStr: '27',
    minRating: 6.5,
    includeTv: false,
  ),
  Mood(
    icon: Icons.public_rounded,
    label: 'mood_doc',
    genreStr: '99',
    minRating: 7.0,
  ),
  Mood(
    icon: Icons.auto_awesome_rounded,
    label: 'mood_fantasy',
    genreStr: '14|878',
  ),
  Mood(icon: Icons.gavel_rounded, label: 'mood_crime', genreStr: '80|53'),
];

/// Ruh hali kısayol çipleri: dokununca zevke göre sıralanmış sonuç
/// ekranına gider (mood bir kısayoldur, sıralama yine kişiseldir).
class MoodChipsRow extends StatelessWidget {
  const MoodChipsRow({super.key});

  void _goMood(BuildContext context, Mood mood) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          genreStr: mood.genreStr,
          minRating: mood.minRating,
          maxRuntime: mood.maxRuntime,
          decade: mood.decade,
          includeTv: mood.includeTv,
          sortBy: 'vote_average.desc',
          // Mood bir kısayoldur, sıralaması yine kullanıcının zevkine göre:
          // aynı "Korku gecesi" iki kullanıcıda farklı dizilir.
          personalRank: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: moods.length,
        itemBuilder: (ctx, i) {
          final m = moods[i];
          return GestureDetector(
            onTap: () => _goMood(context, m),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(m.icon, color: c.red, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)?.get(m.label) ?? m.label,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
