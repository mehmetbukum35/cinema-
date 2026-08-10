import 'package:flutter/material.dart';

const resultsLanguages = [
  (code: 'tr', label: 'Türkçe'),
  (code: 'en', label: 'İngilizce'),
  (code: 'ja', label: 'Japonca'),
  (code: 'ko', label: 'Korece'),
  (code: 'fr', label: 'Fransızca'),
  (code: 'es', label: 'İspanyolca'),
  (code: 'de', label: 'Almanca'),
  (code: 'it', label: 'İtalyanca'),
  (code: 'hi', label: 'Hintçe'),
];

String resultsLanguageFallbackLabel(String code) {
  for (final l in resultsLanguages) {
    if (l.code == code) return l.label;
  }
  if (code.contains('|')) return 'Avrupa';
  return code;
}

String resultsLanguageLabel(String code, String fallback, String localeCode) {
  final isTr = localeCode == 'tr';
  if (code.contains('|')) {
    return isTr ? 'Avrupa' : 'European';
  }
  if (isTr) return fallback;
  switch (code) {
    case 'tr':
      return 'Turkish';
    case 'en':
      return 'English';
    case 'ja':
      return 'Japanese';
    case 'ko':
      return 'Korean';
    case 'fr':
      return 'French';
    case 'es':
      return 'Spanish';
    case 'de':
      return 'German';
    case 'it':
      return 'Italian';
    case 'hi':
      return 'Hindi';
    default:
      return fallback;
  }
}

bool resultsIsYearRangeActive(
  RangeValues range,
  int currentYear, {
  int minYear = 1970,
}) {
  return range.start.round() != minYear || range.end.round() != currentYear;
}
