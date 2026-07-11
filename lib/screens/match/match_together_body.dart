import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../services/prefs_service.dart';
import '../../theme/app_theme.dart';
import 'match_constants.dart';
import 'match_widgets.dart';

/// Couch mode: iki kişinin ortak tür seçimi ve öneri bulma arayüzü.
class MatchTogetherBody extends StatelessWidget {
  final Set<int> p1;
  final Set<int> p2;
  final int activePerson;
  final ValueChanged<int> onPersonChanged;
  final ValueChanged<int> onToggleGenre;
  final VoidCallback onFind;
  final VoidCallback onReset;

  const MatchTogetherBody({
    super.key,
    required this.p1,
    required this.p2,
    required this.activePerson,
    required this.onPersonChanged,
    required this.onToggleGenre,
    required this.onFind,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canFind = p1.isNotEmpty && p2.isNotEmpty;

    return Column(
      children: [
        MatchIntroBanner(
          palette: c,
          icon: Icons.people_rounded,
          title:
              AppLocalizations.of(context)?.get('couch_mode_matcher') ??
              'Couch Mode Matcher',
          description:
              AppLocalizations.of(
                context,
              )?.get('pass_the_phone_to_the_person_n') ??
              'Pass the phone to the person next to you. Both select your favorite genres, and we\'ll discover matches you\'ll both enjoy.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _PersonTab(
                  person: 1,
                  activePerson: activePerson,
                  label:
                      AppLocalizations.of(context)?.get('match_you') ?? 'You',
                  genres: p1,
                  onTap: onPersonChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PersonTab(
                  person: 2,
                  activePerson: activePerson,
                  label:
                      AppLocalizations.of(context)?.get('match_friend') ??
                      'Friend',
                  genres: p2,
                  onTap: onPersonChanged,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              activePerson == 1
                  ? (AppLocalizations.of(
                          context,
                        )?.get('player_1_you_select_your_favor') ??
                        '👉 Player 1 (You): Select your favorite genres...')
                  : (AppLocalizations.of(
                          context,
                        )?.get('player_2_friend_now_its_your_t') ??
                        '👉 Player 2 (Friend): Now it\'s your turn...'),
              key: ValueKey<int>(activePerson),
              style: TextStyle(
                color: activePerson == 1 ? c.red : c.blue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MatchLegendItem(
                color: c.red,
                label: AppLocalizations.of(context)?.get('match_you') ?? 'You',
              ),
              const SizedBox(width: 14),
              MatchLegendItem(
                color: c.blue,
                label:
                    AppLocalizations.of(context)?.get('match_friend') ??
                    'Friend',
              ),
              const SizedBox(width: 14),
              MatchLegendItem(
                color: Colors.purple,
                label:
                    AppLocalizations.of(context)?.get('common_match') ??
                    'Common Match',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (p1.isNotEmpty || p2.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _SelectedChips(p1: p1, p2: p2),
          ),
        ],
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.2,
            ),
            itemCount: togetherGenres.length,
            itemBuilder: (ctx, i) {
              final palette = ctx.c;
              final (id, _) = togetherGenres[i];
              final name = PrefsService.genreName(id);
              final inP1 = p1.contains(id);
              final inP2 = p2.contains(id);
              final inActive = activePerson == 1 ? inP1 : inP2;

              Color borderColor = palette.border;
              Color bgColor = palette.card;
              if (inP1 && inP2) {
                borderColor = Colors.purple;
                bgColor = Colors.purple.withValues(alpha: 0.12);
              } else if (inP1) {
                borderColor = palette.red;
                bgColor = palette.red.withValues(alpha: 0.10);
              } else if (inP2) {
                borderColor = palette.blue;
                bgColor = palette.blue.withValues(alpha: 0.10);
              }

              return GestureDetector(
                onTap: () => onToggleGenre(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: inActive ? borderColor : palette.border,
                      width: inActive ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (inP1)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.red,
                          ),
                        ),
                      if (inP1 && inP2) const SizedBox(width: 3),
                      if (inP2)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.blue,
                          ),
                        ),
                      if (inP1 || inP2) const SizedBox(width: 5),
                      Text(
                        name,
                        style: TextStyle(
                          color: (inP1 || inP2) ? palette.ink : palette.dim,
                          fontSize: 12,
                          fontWeight: (inP1 || inP2)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              if (p1.isNotEmpty || p2.isNotEmpty) ...[
                Semantics(
                  label:
                      AppLocalizations.of(context)?.get('semantics_reset') ??
                      'Seçimleri sıfırla',
                  button: true,
                  child: GestureDetector(
                    onTap: onReset,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: context.c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.c.border, width: 1),
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: context.c.dim,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: canFind ? onFind : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: canFind
                          ? const LinearGradient(
                              colors: [Color(0xFFE94560), Color(0xFFB83050)],
                            )
                          : null,
                      color: canFind ? null : context.c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      canFind
                          ? (AppLocalizations.of(
                                  context,
                                )?.get('match_find_suggestions') ??
                                'Find Common Suggestions')
                          : (AppLocalizations.of(
                                  context,
                                )?.get('match_select_at_least_one') ??
                                'Both choose at least 1 genre'),
                      style: TextStyle(
                        color: canFind ? Colors.white : context.c.textFaint,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonTab extends StatelessWidget {
  final int person;
  final int activePerson;
  final String label;
  final Set<int> genres;
  final ValueChanged<int> onTap;

  const _PersonTab({
    required this.person,
    required this.activePerson,
    required this.label,
    required this.genres,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isActive = activePerson == person;
    final color = person == 1 ? c.red : c.blue;
    return GestureDetector(
      onTap: () => onTap(person),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color : c.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              person == 1 ? Icons.person_rounded : Icons.person_outline_rounded,
              color: isActive ? color : c.dim,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? c.ink : c.dim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context)
                        ?.get('match_genres_count')
                        .replaceAll('{}', genres.length.toString()) ??
                    '${genres.length} genres',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedChips extends StatelessWidget {
  final Set<int> p1;
  final Set<int> p2;

  const _SelectedChips({required this.p1, required this.p2});

  @override
  Widget build(BuildContext context) {
    final intersection = p1.intersection(p2);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final id in p1)
          _GenreChip(
            id: id,
            color: context.c.red,
            icon: intersection.contains(id) ? Icons.favorite_rounded : null,
          ),
        for (final id in p2.difference(p1))
          _GenreChip(id: id, color: context.c.blue),
      ],
    );
  }
}

class _GenreChip extends StatelessWidget {
  final int id;
  final Color color;
  final IconData? icon;

  const _GenreChip({required this.id, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final name = PrefsService.genreName(id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 10),
            const SizedBox(width: 4),
          ],
          Text(
            name,
            style: TextStyle(
              color: context.c.ink,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
