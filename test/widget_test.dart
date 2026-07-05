import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ne_izlesem/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mocks/secure_storage_mock.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Widget Tests for NeIzlesem App', () {
    testWidgets(
      'App should render OnboardingScreen when showOnboarding is true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(child: NeIzlesemApp(showOnboarding: true)),
        );
        await tester
            .pump(); // Settle initial async provider updates (SharedPreferences)

        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pumpAndSettle();

        // Find step 0 title
        expect(find.text('Which movie genres do you like?'), findsOneWidget);
        expect(
          find.text('Select a few genres that interest you to get started'),
          findsOneWidget,
        );

        // Verify that the continue button is rendered
        expect(find.text('Continue'), findsOneWidget);
      },
    );

    testWidgets(
      'App should render MainShell and bottom tabs when showOnboarding is false',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(child: NeIzlesemApp(showOnboarding: false)),
        );
        await tester
            .pump(); // Settle initial async provider updates (SharedPreferences)
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pump(const Duration(milliseconds: 480));
        await tester.pump();

        // Find bottom navigation bar items
        expect(find.text('Browse'), findsOneWidget);
        expect(find.text('Rate'), findsOneWidget);
        expect(find.text('Together'), findsOneWidget);
        expect(find.text('Search'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
      },
    );

    testWidgets(
      'App should change tab in MainShell when navigating through bottom tabs',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(child: NeIzlesemApp(showOnboarding: false)),
        );
        await tester
            .pump(); // Settle initial async provider updates (SharedPreferences)
        await tester.pump(const Duration(milliseconds: 2600));
        await tester.pump(const Duration(milliseconds: 380));
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pump(const Duration(milliseconds: 480));
        await tester.pump();

        // Tap on 'Search' tab
        await tester.tap(find.text('Search'));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump();

        // Tap on 'Profile' tab
        await tester.tap(find.text('Profile'));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump();
      },
    );
  });
}
