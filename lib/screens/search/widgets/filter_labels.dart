import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';

/// Arama filtre etiketleri için dil, platform ve puan yardımcıları.
class SearchFilterLabels {
  static const providers = {
    8: 'Netflix',
    11: 'MUBI',
    119: 'Prime',
    337: 'Disney+',
  };

  static final ratings = {6.0: '6+', 7.0: '7+', 7.5: '7.5+', 8.0: '8+'};

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

  static String languageLabel(BuildContext context, String lang) {
    final localizations = AppLocalizations.of(context);
    return switch (lang) {
      'ko' => localizations?.get('lang_ko') ?? 'Korean Cinema',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl' =>
        localizations?.get('lang_eu') ?? 'European Cinema',
      'en' => localizations?.get('lang_en') ?? 'Hollywood',
      'tr' => localizations?.get('lang_tr') ?? 'Turkish Cinema',
      'ja' => localizations?.get('lang_ja') ?? 'Japanese Cinema',
      'hi' => localizations?.get('lang_hi') ?? 'Bollywood',
      'fa' => localizations?.get('lang_fa') ?? 'Iranian Cinema',
      _ => lang,
    };
  }

  /// Chip / ızgara için kısa etiket (satır kırılmasını azaltır).
  static String languageShort(BuildContext context, String lang) {
    final l = AppLocalizations.of(context);
    return switch (lang) {
      'ko' => l?.get('culture_short_korean') ?? 'Kore',
      'fr|es|de|it|pt|sv|da|no|fi|nl|pl' =>
        l?.get('culture_short_european') ?? 'Avrupa',
      'en' => l?.get('culture_short_hollywood') ?? 'Hollywood',
      'tr' => l?.get('culture_short_turkish') ?? 'Türk',
      'ja' => l?.get('culture_short_japanese') ?? 'Japon',
      'hi' => l?.get('culture_short_indian') ?? 'Hint',
      'fa' => l?.get('culture_short_iranian') ?? 'İran',
      _ => languageLabel(context, lang),
    };
  }

  static IconData languageIcon(String lang) => switch (lang) {
    'ko' => Icons.auto_awesome_rounded,
    'fr|es|de|it|pt|sv|da|no|fi|nl|pl' => Icons.public_rounded,
    'en' => Icons.movie_filter_rounded,
    'tr' => Icons.theaters_rounded,
    'ja' => Icons.brightness_5_rounded,
    'hi' => Icons.music_note_rounded,
    'fa' => Icons.camera_alt_rounded,
    _ => Icons.public_rounded,
  };
}
