import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/prefs_service.dart';
import 'services/localization_service.dart';
import 'services/notification_service.dart';
import 'services/providers.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.navBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase'i arka planda başlat (blokajı kaldır)
  unawaited(Future(() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e, st) {
      // Firebase başlatılamazsa push devre dışı kalır; çekirdek uygulama etkilenmez.
      debugPrint("Firebase background initialization failed: $e\n$st");
    }
  }));

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
    );

    return MaterialApp(
      title: 'Ne İzlesem?',
      navigatorKey: NotificationService.navigatorKey,
      locale: currentLocale,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) return const Locale('en', 'US');
        for (var supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale.languageCode) {
            return supportedLocale;
          }
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
