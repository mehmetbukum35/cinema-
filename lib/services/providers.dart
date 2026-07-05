import 'dart:ui' as ui;
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tmdb_service.dart';
import 'db_helper.dart';
import 'prefs_service.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en', 'US')) {
    _init();
  }

  void _init() async {
    final saved = await PrefsService.getSelectedLanguage();
    if (saved != null) {
      state = Locale(saved);
      PrefsService.activeLanguageCode = saved;
    } else {
      final sysLang = ui.PlatformDispatcher.instance.locale.languageCode;
      final supported = ['tr', 'en'].contains(sysLang) ? sysLang : 'en';
      state = Locale(supported);
      PrefsService.activeLanguageCode = supported;
    }
  }

  Future<void> setLocale(String langCode) async {
    await PrefsService.setSelectedLanguage(langCode);
    state = Locale(langCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

/// Tema modu (koyu/açık). Varsayılan koyu; kullanıcı seçimi cihazda saklanır.
/// Koyu tema mevcut görünümü AYNEN korur — açık tema yalnızca alternatiftir.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _init();
  }

  void _init() async {
    state = _parse(await PrefsService.getThemeMode());
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static String _str(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    await PrefsService.setThemeMode(_str(mode));
    state = mode;
  }

  Future<void> toggle() =>
      setMode(state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

final tmdbServiceProvider = Provider<TmdbService>((ref) {
  final locale = ref.watch(localeProvider);
  final isTr = locale.languageCode == 'tr';
  return TmdbService(
    language: isTr ? 'tr-TR' : 'en-US',
    region: isTr ? 'TR' : 'US',
  );
});

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

final browseScrollTriggerProvider = StateProvider<int>((ref) => 0);

class OfflineNotifier extends StateNotifier<bool> {
  Timer? _timer;

  OfflineNotifier() : super(false) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _checkConnectivity();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkConnectivity());
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('example.com').timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted) {
        state = !isOnline;
      }
    } catch (_) {
      if (mounted) {
        state = true;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final offlineProvider = StateNotifierProvider<OfflineNotifier, bool>((ref) {
  return OfflineNotifier();
});

final browsePopularPageProvider = Provider<int>((ref) {
  return 1 + Random().nextInt(5);
});
