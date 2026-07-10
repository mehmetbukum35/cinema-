import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/prefs_service.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

class FamilyModeCard extends StatefulWidget {
  const FamilyModeCard({super.key});

  @override
  State<FamilyModeCard> createState() => _FamilyModeCardState();
}

class _FamilyModeCardState extends State<FamilyModeCard> {
  bool _familyMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFamilyMode();
  }

  Future<void> _loadFamilyMode() async {
    final val = await PrefsService.isFamilyMode();
    if (mounted) {
      setState(() {
        _familyMode = val;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFamilyMode(bool value) async {
    HapticFeedback.lightImpact();
    await PrefsService.setFamilyMode(value);
    if (mounted) {
      setState(() {
        _familyMode = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_loading) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: c.isLight ? Border.all(color: c.border, width: 1) : null,
        boxShadow: c.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.green.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.family_restroom_rounded,
              color: c.green,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.get('profile_family_mode') ??
                      'Aile Dostu Mod (PG-13)',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                        context,
                      )?.get('filters_out_deadpool_euphoria_') ??
                      'Filters out Deadpool, Euphoria, and mature R-rated content.',
                  style: TextStyle(color: c.dim, fontSize: 11.5, height: 1.25),
                ),
              ],
            ),
          ),
          Switch(
            value: _familyMode,
            activeThumbColor: c.green,
            onChanged: _toggleFamilyMode,
          ),
        ],
      ),
    );
  }
}
