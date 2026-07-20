import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' as ui;
import 'firebase_options.dart';
import 'screens/onboarding_screen.dart';
import 'dart:convert';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/prefs_service.dart';
import 'services/db_helper.dart';
import 'services/localization_service.dart';
import 'services/notification_service.dart';
import 'services/providers.dart';
import 'services/taste_dna_presenter.dart';
import 'services/app_config.dart';
import 'services/crash_reporting_service.dart';
import 'theme/app_theme.dart';

void main() {
  runZonedGuarded(
    _bootstrap,
    (error, stack) => CrashReportingService.record(
      error,
      stack,
      fatal: true,
      reason: 'Uncaught asynchronous error',
    ),
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Taste DNA theme lexicons (TR translations + EN display labels)
  Future<void> loadLexicon(
    String asset,
    void Function(Map<String, String>) assign,
  ) async {
    try {
      final jsonStr = await rootBundle.loadString(asset);
      final Map<String, dynamic> decoded = json.decode(jsonStr);
      assign(decoded.map((k, v) => MapEntry(k, v.toString())));
    } catch (e) {
      debugPrint('Failed to load $asset at startup: $e');
    }
  }

  await loadLexicon(
    'assets/lexicon/theme_tr.json',
    (m) => TasteDnaPresenter.themeTr = m,
  );
  await loadLexicon(
    'assets/lexicon/theme_en.json',
    (m) => TasteDnaPresenter.themeEn = m,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.navBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase: FCM token alınmadan önce hazır olmalı (NotificationService race'i önler).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CrashReportingService.initialize();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashReportingService.record(
        details.exception,
        details.stack ?? StackTrace.current,
        fatal: true,
        reason: details.context?.toDescription(),
      );
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      CrashReportingService.record(
        error,
        stack,
        fatal: true,
        reason: 'Uncaught platform error',
      );
      return true;
    };
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    // Firebase başlatılamazsa push devre dışı kalır; çekirdek uygulama etkilenmez.
    debugPrint("Firebase initialization failed: $e\n$st");
  }

  // TMDB cache verilerinden süresi dolanları arka planda temizle (30 günlük limit)
  AppConfig.warnIfProductionApiWithoutDefine();
  unawaited(
    Future(() async {
      try {
        await DatabaseHelper().deleteExpiredTmdbCache(30 * 24 * 60 * 60 * 1000);
      } catch (e) {
        debugPrint("Error clearing expired TMDB cache at startup: $e");
      }
    }),
  );

  final onboardingDone = await PrefsService.isOnboardingDone();
  runApp(ProviderScope(child: NeIzlesemApp(showOnboarding: !onboardingDone)));
}

class NeIzlesemApp extends ConsumerWidget {
  final bool showOnboarding;
  const NeIzlesemApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    const pageTransitions = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    );

    // ── Koyu tema (MEVCUT görünüm — değiştirilmedi) ──────────────────────────
    final darkBase = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.red,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        surfaceTint: Colors.transparent,
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
    );
    final darkTheme = darkBase.copyWith(
      textTheme: CinemaText.theme(darkBase.textTheme),
      pageTransitionsTheme: pageTransitions,
      // Marka kırmızısı (#E94560) üstünde beyaz ~3.8:1; dolgu koyulaştırılır.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.crimson,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.crimson,
          foregroundColor: Colors.white,
        ),
      ),
    );

    // ── Açık tema (ALTERNATİF — sıcak/sinematik beyaz) ───────────────────────
    final lightBase = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColorsLight.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColorsLight.red,
        secondary: AppColorsLight.gold,
        surface: AppColorsLight.surface,
        onSurface: AppColorsLight.ink,
        surfaceTint: Colors.transparent,
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
    );
    final lightTheme = lightBase.copyWith(
      textTheme: CinemaText.lightTheme(lightBase.textTheme),
      pageTransitionsTheme: pageTransitions,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorsLight.crimson,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColorsLight.crimson,
          foregroundColor: Colors.white,
        ),
      ),
    );

    return MaterialApp(
      title: 'Cinema+ | What to Watch?',
      navigatorKey: NotificationService.navigatorKey,
      locale: currentLocale,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale != null && locale.languageCode == 'tr') {
          return const Locale('tr', 'TR');
        }
        return const Locale('en', 'US');
      },
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: mediaQueryData.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child!,
        );
      },
      home: SplashScreen(
        next: showOnboarding ? const OnboardingScreen() : const MainShell(),
      ),
    );
  }
}
