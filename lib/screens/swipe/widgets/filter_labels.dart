import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';

/// Swipe filtre etiketleri için dil ve platform yardımcıları.
class SwipeFilterLabels {
  static const providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime Video',
    337: 'Disney+',
  };

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

  static String languageLabel(BuildContext context, String? lang) {
    if (lang == null) {
      return AppLocalizations.of(context)?.get('lang_all') ?? 'Tümü';
    }
    return languages(context)[lang] ??
        (AppLocalizations.of(context)?.get('lang_unknown') ?? 'Bilinmeyen');
  }

  static String providerLabel(BuildContext context, int? providerId) {
    final localizations = AppLocalizations.of(context);
    if (providerId == null) {
      return localizations?.get('lang_all') ?? 'All';
    }
    return providers[providerId] ??
        (localizations?.get('lang_unknown') ?? 'Unknown');
  }
}
