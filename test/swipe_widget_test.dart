import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/screens/swipe_screen.dart';
import 'package:ne_izlesem/services/localization_service.dart';
import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('swipe_guide_shown', true);
  });

  group('SwipeScreen Widget and Interaction Tests', () {
    testWidgets('SwipeScreen should display movie details and rate them', (
      WidgetTester tester,
    ) async {
      // Mock TMDB responses
      final mockMovies = {
        'results': [
          {
            'id': 1001,
            'title': 'Swipe Widget Test Movie',
            'overview': 'Incredible overview.',
            'vote_average': 8.7,
            'release_date': '2026-06-23',
            'genre_ids': [28],
            'poster_path': '/mock_poster.jpg',
            'vote_count': 100,
          },
        ],
      };
      final mockTv = {'results': []};

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/3/movie/popular') ||
            request.url.path.endsWith('/3/discover/movie')) {
          return http.Response(jsonEncode(mockMovies), 200);
        } else if (request.url.path.endsWith('/3/tv/popular') ||
            request.url.path.endsWith('/3/discover/tv')) {
          return http.Response(jsonEncode(mockTv), 200);
        }
        return http.Response('Not Found', 404);
      });

      final mockService = TmdbService(client: client);

      // Pump SwipeScreen overriding the service provider
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tmdbServiceProvider.overrideWithValue(mockService)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('tr', 'TR'),
            home: SwipeScreen(),
          ),
        ),
      );

      // Wait for initialization and network requests to resolve
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(); // trigger anim frame

      // Loading should end and movie title should render
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Swipe Widget Test Movie'), findsOneWidget);
      expect(find.text('(2026)'), findsOneWidget);
      expect(find.text('0 değerlendirme'), findsOneWidget);

      // Tap on 'Harika' rating button
      await tester.tap(find.text('Harika'));
      await tester.pump(); // start fade reverse
      await tester.pump(const Duration(milliseconds: 250)); // resolve animation
      await tester.pump(); // render next frame

      // Queue is empty now (loading text shows up)
      expect(find.text('Daha fazla yükleniyor...'), findsOneWidget);

      // Verify that rating is saved in shared preferences mock database
      final ratedIds = await PrefsService.getRatedIds();
      expect(ratedIds.contains('movie_1001'), isTrue);
    });

    testWidgets(
      'rapid double-tap rates only one card (re-entrancy guard)',
      (WidgetTester tester) async {
        // İki farklı film: hızlı çift dokunuş guard'sızken ikincisini
        // atlayıp aynı kartı iki kez puanlıyordu (current imleci 0→2).
        final mockMovies = {
          'results': [
            {
              'id': 3001,
              'title': 'Reentrancy Movie One',
              'overview': 'First.',
              'vote_average': 8.0,
              'release_date': '2026-01-01',
              'genre_ids': [28],
              'poster_path': '/one.jpg',
              'vote_count': 100,
            },
            {
              'id': 3002,
              'title': 'Reentrancy Movie Two',
              'overview': 'Second.',
              'vote_average': 7.0,
              'release_date': '2026-02-01',
              'genre_ids': [28],
              'poster_path': '/two.jpg',
              'vote_count': 100,
            },
          ],
        };
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/3/movie/popular') ||
              request.url.path.endsWith('/3/discover/movie')) {
            return http.Response(jsonEncode(mockMovies), 200);
          }
          return http.Response('{"results": []}', 200);
        });
        final mockService = TmdbService(client: client);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [tmdbServiceProvider.overrideWithValue(mockService)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('tr', 'TR'),
              home: SwipeScreen(),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();

        expect(find.text('0 değerlendirme'), findsOneWidget);

        // İlk dokunuş _rate#1'i başlatır: _busy=true, 200 ms fade reverse
        // beklemeye girer. Aralarında pump YOK — ikinci dokunuş _busy hâlâ
        // true iken tanınır ve guard tarafından yok sayılmalı.
        await tester.tap(find.text('Harika'));
        await tester.tap(find.text('Harika'));
        await tester.pump();

        // Animasyonu ve bekleyen microtask'ları çöz (pumpAndSettle,
        // CinematicBackground'ın sonsuz animasyonu yüzünden kullanılamaz).
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        // Yalnızca BİR kart puanlanmış olmalı (guard yoksa "2 değerlendirme"
        // ve ikinci kart atlanırdı).
        expect(find.text('1 değerlendirme'), findsOneWidget);
        expect(find.text('2 değerlendirme'), findsNothing);
        final ratedIds = await PrefsService.getRatedIds();
        expect(ratedIds.length, 1);
      },
    );

    testWidgets(
      'SwipeScreen should show gesture guide overlay when not shown before',
      (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues({});
        await PrefsService.resetAll();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('swipe_guide_shown', false);

        final client = MockClient(
          (request) async => http.Response('{"results": []}', 200),
        );
        final mockService = TmdbService(client: client);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [tmdbServiceProvider.overrideWithValue(mockService)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('en', 'US'),
              home: SwipeScreen(),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();

        // Gesture guide overlay should be shown
        expect(find.text('Discovery Gestures'), findsOneWidget);
        expect(find.text('Swipe Right'), findsOneWidget);
        expect(find.text('Swipe Left'), findsOneWidget);

        // Tap on 'Got it, Let's Start!' button
        await tester.tap(find.text('Got it, Let\'s Start!'));
        await tester.pump(const Duration(milliseconds: 200));

        // Overlay should be dismissed
        expect(find.text('Discovery Gestures'), findsNothing);
        expect(await PrefsService.isSwipeGuideShown(), isTrue);
      },
    );
  });
}
