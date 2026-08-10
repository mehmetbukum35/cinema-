import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/screens/browse_screen.dart';
import 'package:ne_izlesem/screens/browse/browse_guest_list_card.dart';
import 'package:ne_izlesem/screens/browse/friends_activity_teaser.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/widgets/shimmer.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  responsiveTestWidgets(
    'BrowseScreen loading layout remains responsive',
    (testCase) => pumpApp(
      const BrowseScreen(),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
      overrides: [tmdbServiceProvider.overrideWithValue(emptyTmdbService())],
    ),
    verify: (tester, testCase) async {
      expect(find.byType(Shimmer), findsWidgets);
    },
  );

  testWidgets('guest teaser explains friends activity on Discover', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpApp(const CustomScrollView(slivers: [BrowseFriendsActivityTeaser()])),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BrowseFriendsActivityTeaser), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Open Together'), findsOneWidget);
  });

  testWidgets('guest list card shows the user own posters and a publish CTA', (
    tester,
  ) async {
    final preview = GuestListPreview(
      posters: [
        Movie(
          id: 1,
          title: 'A',
          overview: '',
          voteAverage: 8,
          posterPath: '/a.jpg',
        ),
        Movie(
          id: 2,
          title: 'B',
          overview: '',
          voteAverage: 8,
          posterPath: '/b.jpg',
        ),
        Movie(
          id: 3,
          title: 'C',
          overview: '',
          voteAverage: 8,
          posterPath: '/c.jpg',
        ),
      ],
      likedCount: 3,
    );

    await tester.pumpWidget(
      pumpApp(
        SizedBox(height: 200, child: BrowseGuestListCard(preview: preview)),
      ),
    );
    await tester.pump();

    expect(find.text('Your List'), findsOneWidget);
    expect(find.text('not published'), findsOneWidget);
    expect(find.text('Sign in and publish'), findsOneWidget);
  });
}
