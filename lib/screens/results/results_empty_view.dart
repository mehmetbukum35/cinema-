import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class ResultsEmptyView extends StatelessWidget {
  const ResultsEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.dim.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.search_off_rounded, color: c.dim, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.get('search_no_results') ??
                'Sonuç bulunamadı',
            style: TextStyle(
              color: c.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.get('try_different_filters') ??
                'Try different filters',
            style: TextStyle(color: c.dim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
