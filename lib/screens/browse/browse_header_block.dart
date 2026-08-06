import 'package:flutter/material.dart';

import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Keşfet üst başlık: "what to" + "watch?".
class BrowseHeaderBlock extends StatelessWidget {
  const BrowseHeaderBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context)?.get('what_to') ?? 'what to ',
            style: TextStyle(
              color: c.ink,
              fontSize: 28,
              fontWeight: FontWeight.w300,
            ),
          ),
          Text(
            AppLocalizations.of(context)?.get('watch') ?? 'watch?',
            style: TextStyle(
              color: c.ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
