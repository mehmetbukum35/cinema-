import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../l10n/en.dart';
import '../l10n/tr.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = [
    Locale('tr', 'TR'),
    Locale('en', 'US'),
  ];

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': kEnStrings,
    'tr': kTrStrings,
  };

  String get(String key) {
    final languageCode = locale.languageCode;
    if (_localizedValues[languageCode]?.containsKey(key) ?? false) {
      return _localizedValues[languageCode]![key]!;
    }
    if (_localizedValues['en']?.containsKey(key) ?? false) {
      return _localizedValues['en']![key]!;
    }
    return key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'tr'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
