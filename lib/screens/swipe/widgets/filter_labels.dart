import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';

/// Swipe filtre etiketleri için dil ve platform yardımcıları.
class SwipeFilterLabels {
  static const providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime',
    337: 'Disney+',
  };

  static const languageOrder = [
    'ko',
    'fr|es|de|it|pt|sv|da|no|fi|nl|pl',
    'en',
    'tr',
    'ja',
    'hi',
    'fa',
  ];

  static Map<String, String> languages(BuildContext context) => {
    for (final key in languageOrder) key: languageLabel(context, key),
  };

  static String languageLabel(BuildContext context, String? lang) {
    final localizations = AppLocalizations.of(context);
    if (lang == null) {
      return localizations?.get('lang_all') ?? 'All';
    }
    return switch (lang) {
      'ko' => localizations?.get('lang_ko') ?? 'Korean Cinema',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl' =>
        localizations?.get('lang_eu') ?? 'European Cinema',
      'en' => localizations?.get('lang_en') ?? 'English-language',
      'tr' => localizations?.get('lang_tr') ?? 'Turkish Cinema',
      'ja' => localizations?.get('lang_ja') ?? 'Japanese Cinema',
      'hi' => localizations?.get('lang_hi') ?? 'Bollywood',
      'fa' => localizations?.get('lang_fa') ?? 'Iranian Cinema',
      _ => localizations?.get('lang_unknown') ?? 'Unknown',
    };
  }

  static String languageShort(BuildContext context, String? lang) {
    final l = AppLocalizations.of(context);
    if (lang == null) return l?.get('lang_all') ?? 'All';
    return switch (lang) {
      'ko' => l?.get('culture_short_korean') ?? 'Kore',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl' =>
        l?.get('culture_short_european') ?? 'Avrupa',
      'en' => l?.get('lang_en_short') ?? 'English',
      'tr' => l?.get('culture_short_turkish') ?? 'Türk',
      'ja' => l?.get('culture_short_japanese') ?? 'Japon',
      'hi' => l?.get('culture_short_indian') ?? 'Hint',
      'fa' => l?.get('culture_short_iranian') ?? 'İran',
      _ => languageLabel(context, lang),
    };
  }

  static IconData languageIcon(String? lang) => switch (lang) {
    null => Icons.travel_explore_rounded,
    'ko' => Icons.auto_awesome_rounded,
    'fr|es|de|it|pt|sv|da|no|fi|nl|pl' => Icons.public_rounded,
    'en' => Icons.movie_filter_rounded,
    'tr' => Icons.theaters_rounded,
    'ja' => Icons.brightness_5_rounded,
    'hi' => Icons.music_note_rounded,
    'fa' => Icons.camera_alt_rounded,
    _ => Icons.public_rounded,
  };

  static String providerLabel(BuildContext context, int? providerId) {
    final localizations = AppLocalizations.of(context);
    if (providerId == null) {
      return localizations?.get('lang_all') ?? 'All';
    }
    return providers[providerId] ??
        (localizations?.get('lang_unknown') ?? 'Unknown');
  }
}
