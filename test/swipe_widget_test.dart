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
          child: const MaterialApp(home: SwipeScreen()),
        ),
      );

      // Initial loading indicator should show
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for initialization and network requests to resolve
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(); // trigger anim frame

      // Loading should end and movie title should render
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Swipe Widget Test Movie'), findsOneWidget);
      expect(find.text('(2026)'), findsOneWidget);
      expect(find.text('0 ratings'), findsOneWidget);

      // Tap on 'Harika' rating button
      await tester.tap(find.text('Harika'));
      await tester.pump(); // start fade reverse
      await tester.pump(const Duration(milliseconds: 250)); // resolve animation
      await tester.pump(); // render next frame

      // Queue is empty now (loading text shows up)
      expect(find.text('Loading more...'), findsOneWidget);

      // Verify that rating is saved in shared preferences mock database
      final ratedIds = await PrefsService.getRatedIds();
      expect(ratedIds.contains('movie_1001'), isTrue);
    });

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
            child: const MaterialApp(home: SwipeScreen()),
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
