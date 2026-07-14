import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';

/// Arama filtre etiketleri için dil, platform ve puan yardımcıları.
class SearchFilterLabels {
  static const providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime Video',
    337: 'Disney+',
  };

  static final ratings = {6.0: '6.0+', 7.0: '7.0+', 7.5: '7.5+', 8.0: '8.0+'};

  static Map<String, String> languages(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return {
      'ko': localizations?.get('lang_ko') ?? 'Kore Sineması',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl':
          localizations?.get('lang_eu') ?? 'Avrupa Sineması',
      'en': localizations?.get('lang_en') ?? 'Hollywood',
      'tr': localizations?.get('lang_tr') ?? 'Türk Sineması',
      'ja': localizations?.get('lang_ja') ?? 'Japon Sineması',
      'hi': localizations?.get('lang_hi') ?? 'Bollywood',
      'fa': localizations?.get('lang_fa') ?? 'İran Sineması',
    };
  }

  static String languageLabel(BuildContext context, String lang) {
    return languages(context)[lang] ?? lang;
  }
}
