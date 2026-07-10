import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

/// Detay sayfası bölüm başlığı: yereldeki karşılığı büyük harfle basar.
class DetailSectionLabel extends StatelessWidget {
  final String labelKey;
  const DetailSectionLabel(this.labelKey, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)?.get(labelKey) ?? labelKey;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.c.dim,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    );
  }
}
