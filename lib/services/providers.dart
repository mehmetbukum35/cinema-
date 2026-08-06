import 'dart:ui' as ui;
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
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
import '../models/discovery_context.dart';

/// Açılışta diskten okunmuş dil kodu. `main()` gerçek değerle override eder;
/// override yoksa (veya kayıt yoksa) `null` gelir ve platform diline düşülür.
/// Testler bu provider'ı override ederek dili senkron olarak sabitleyebilir.
final initialLocaleProvider = Provider<String?>((ref) => null);

/// Seçili arayüz dilinin tek sahibi. Diğer katmanlar dili buradan enjekte
/// edilen bir okuyucuyla alır; global bir kopya tutulmaz — iki yazıcı
/// ayrıştığında kullanıcı Türkçe arayüzde İngilizce bildirim alıyordu.
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(String? initialLanguageCode)
    : super(Locale(_resolve(initialLanguageCode)));

  /// Dil çözümü tek yerde: kayıtlı tercih varsa o, yoksa platform dili;
  /// desteklenmeyen her dil 'en'e düşer.
  static String _resolve(String? saved) {
    if (saved == 'tr' || saved == 'en') return saved!;
    final sysLang = ui.PlatformDispatcher.instance.locale.languageCode;
    return sysLang == 'tr' ? 'tr' : 'en';
  }

  Future<void> setLocale(String langCode) async {
    await PrefsService.setSelectedLanguage(langCode);
    state = Locale(langCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(ref.watch(initialLocaleProvider));
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
  return RecommendationEngine(
    ref.watch(tmdbServiceProvider),
    localeCode: () => ref.read(localeProvider).languageCode,
  );
});

/// Sinema DNA motoru — puanlama verisinden zevk kimliği üretir.
final tasteDnaServiceProvider = Provider<TasteDnaService>((ref) {
  return TasteDnaService(ref.watch(tmdbServiceProvider));
});

final browseScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Keşfet ekranını arka planda yeniden yükle (giriş + sync, dil değişimi dışı).
final browseRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Yalnızca aktif keşif oturumunu etkiler; kalıcı Taste DNA'ya yazılmaz.
final discoveryContextProvider = StateProvider<DiscoveryContext>(
  (ref) => const DiscoveryContext(),
);

class OfflineNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  Timer? _timer;
  final Future<bool> Function() _probe;
  var _checkGeneration = 0;
  var _observing = false;

  OfflineNotifier({Future<bool> Function()? probe, bool autoStart = true})
    : _probe = probe ?? _probeApi,
      super(false) {
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!autoStart || isTest) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    checkNow();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => checkNow());
  }

  static Future<bool> _probeApi() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/health');
    final response = await http.get(uri).timeout(const Duration(seconds: 3));
    return response.statusCode == 200 && response.body.contains('"ok"');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkNow();
    }
  }

  Future<void> checkNow() async {
    final generation = ++_checkGeneration;
    try {
      final isOnline = await _probe();
      if (mounted && generation == _checkGeneration) {
        state = !isOnline;
      }
    } catch (e) {
      // API erişimi başarısız olduysa veya zaman aşımına uğradıysa cihaz çevrimdışıdır.
      if (mounted && generation == _checkGeneration) {
        state = true;
      }
    }
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
    }
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
