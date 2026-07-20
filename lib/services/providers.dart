import 'dart:ui' as ui;
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart'
    show
        Locale,
        ThemeMode,
        WidgetsBinding,
        WidgetsBindingObserver,
        AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'tmdb_service.dart';
import 'db_helper.dart';
import 'prefs_service.dart';
import 'recommendation_engine.dart';
import 'taste_dna_service.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(_getInitialLocale()) {
    _init();
  }

  static Locale _getInitialLocale() {
    final sysLang = ui.PlatformDispatcher.instance.locale.languageCode;
    final supported = ['tr', 'en'].contains(sysLang) ? sysLang : 'en';
    return Locale(supported);
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
    PrefsService.activeLanguageCode = langCode;
    state = Locale(langCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

/// Tema modu (koyu/açık). Varsayılan açık; kullanıcı seçimi cihazda saklanır.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _init();
  }

  void _init() async {
    state = _parse(await PrefsService.getThemeMode());
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
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
  final String tmdbLang;
  final String tmdbRegion;
  switch (locale.languageCode) {
    case 'tr':
      tmdbLang = 'tr-TR';
      tmdbRegion = 'TR';
      break;
    case 'en':
    default:
      tmdbLang = 'en-US';
      tmdbRegion = 'US';
      break;
  }
  return TmdbService(language: tmdbLang, region: tmdbRegion);
});

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

/// Ortak öneri motoru — swipe kuyruğu ve Sana Özel aynı örneği paylaşır ki
/// keyword zevk vektörü memoization'ı ve invalidation'ı tek yerden yönetilsin.
final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return RecommendationEngine(ref.watch(tmdbServiceProvider));
});

/// Sinema DNA motoru — puanlama verisinden zevk kimliği üretir.
final tasteDnaServiceProvider = Provider<TasteDnaService>((ref) {
  return TasteDnaService(ref.watch(tmdbServiceProvider));
});

final browseScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Keşfet ekranını arka planda yeniden yükle (giriş + sync, dil değişimi dışı).
final browseRefreshTriggerProvider = StateProvider<int>((ref) => 0);

class OfflineNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  Timer? _timer;

  OfflineNotifier() : super(false) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    WidgetsBinding.instance.addObserver(this);
    _checkConnectivity();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      final isOnline =
          response.statusCode == 200 && response.body.contains('"ok"');
      if (mounted) {
        state = !isOnline;
      }
    } catch (e) {
      // API erişimi başarısız olduysa veya zaman aşımına uğradıysa cihaz çevrimdışıdır.
      if (mounted) {
        state = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
