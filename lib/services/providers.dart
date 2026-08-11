import 'dart:ui' as ui;
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show
        Locale,
        ThemeMode,
        WidgetsBinding,
        WidgetsBindingObserver,
        AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'tmdb_service.dart';
import 'db_helper.dart';
import 'prefs/app_settings.dart';
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
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => Locale(_resolve(ref.watch(initialLocaleProvider)));

  /// Dil çözümü tek yerde: kayıtlı tercih varsa o, yoksa platform dili;
  /// desteklenmeyen her dil 'en'e düşer.
  static String _resolve(String? saved) {
    if (saved == 'tr' || saved == 'en') return saved!;
    final sysLang = ui.PlatformDispatcher.instance.locale.languageCode;
    return sysLang == 'tr' ? 'tr' : 'en';
  }

  Future<void> setLocale(String langCode) async {
    await PrefsAppSettings.setSelectedLanguage(langCode);
    state = Locale(langCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);

/// Tema modu (koyu/açık). Varsayılan açık; kullanıcı seçimi cihazda saklanır.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Diskten okuma asenkron; ilk kare açık temayla çizilir, kayıtlı tercih
    // gelince state güncellenir.
    _init();
    return ThemeMode.light;
  }

  void _init() async {
    final saved = _parse(await PrefsAppSettings.getThemeMode());
    // Provider okuma tamamlanmadan atılmış olabilir (kısa ömürlü test
    // container'ı, hot restart); dispose sonrası state yazmak hata fırlatır.
    if (!ref.mounted) return;
    state = saved;
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
    await PrefsAppSettings.setThemeMode(_str(mode));
    state = mode;
  }

  Future<void> toggle() =>
      setMode(state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

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

/// Tek yönlü sayaç tetikleyici: değer taşımaz, yalnız "yeniden bir şey oldu"
/// sinyali verir. Dinleyiciler `ref.listen` ile artışı yakalar.
class TriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Dinleyicileri bir kez uyandırır.
  void fire() => state++;
}

final browseScrollTriggerProvider = NotifierProvider<TriggerNotifier, int>(
  TriggerNotifier.new,
);

/// Keşfet ekranını arka planda yeniden yükle (giriş + sync, dil değişimi dışı).
final browseRefreshTriggerProvider = NotifierProvider<TriggerNotifier, int>(
  TriggerNotifier.new,
);

/// Yalnızca aktif keşif oturumunu etkiler; kalıcı Taste DNA'ya yazılmaz.
class DiscoveryContextNotifier extends Notifier<DiscoveryContext> {
  @override
  DiscoveryContext build() => const DiscoveryContext();

  void setContext(DiscoveryContext context) => state = context;

  void update(DiscoveryContext Function(DiscoveryContext current) transform) =>
      state = transform(state);
}

final discoveryContextProvider =
    NotifierProvider<DiscoveryContextNotifier, DiscoveryContext>(
      DiscoveryContextNotifier.new,
    );

/// Çevrimdışı yoklamasının enjekte edilebilir ucu. Testler bunu override
/// ederek ağa hiç çıkmadan yarış senaryosu kurar; üretimde /health'e gider.
final offlineProbeProvider = Provider<Future<bool> Function()>(
  (ref) => OfflineNotifier._probeApi,
);

class OfflineNotifier extends Notifier<bool> with WidgetsBindingObserver {
  Timer? _timer;
  var _checkGeneration = 0;
  var _observing = false;

  @override
  bool build() {
    ref.onDispose(_teardown);

    // Testlerde periyodik zamanlayıcı ve gerçek ağ yoklaması istemiyoruz;
    // test kendi tempolu probe'unu override edip checkNow'ı elle sürer.
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      checkNow();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => checkNow());
    }
    return false;
  }

  static Future<bool> _probeApi() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/health');
    final response = await http.get(uri).timeout(const Duration(seconds: 3));
    // 429/503 = sunucu ayakta ama kısıtlı; cihazı offline sayma.
    if (response.statusCode == 429 || response.statusCode == 503) {
      return true;
    }
    if (response.statusCode != 200) return false;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['ok'] == true) return true;
    } catch (_) {
      // Eski/düz metin health yanıtı
      if (response.body.contains('"ok"')) return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkNow();
    }
  }

  Future<void> checkNow() async {
    final generation = ++_checkGeneration;
    final probe = ref.read(offlineProbeProvider);
    try {
      final isOnline = await probe();
      if (ref.mounted && generation == _checkGeneration) {
        state = !isOnline;
      }
    } catch (e) {
      // API erişimi başarısız olduysa veya zaman aşımına uğradıysa cihaz çevrimdışıdır.
      if (ref.mounted && generation == _checkGeneration) {
        state = true;
      }
    }
  }

  void _teardown() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _timer?.cancel();
    _timer = null;
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, bool>(
  OfflineNotifier.new,
);

final browsePopularPageProvider = Provider<int>((ref) {
  return 1 + Random().nextInt(5);
});
