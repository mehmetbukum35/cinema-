import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../theme/app_theme.dart';

/// Film/dizi aramalarında yapım yılıyla sonuçların daraltılabildiğini gösterir.
class SearchYearHint extends StatelessWidget {
  const SearchYearHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text =
        AppLocalizations.of(context)?.get('search_year_tip') ??
        'Aynı adlı yapımları daha kolay bulmak için adın yanına yayın yılını da yazabilirsiniz.';

    return Semantics(
      label: text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.dim, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
