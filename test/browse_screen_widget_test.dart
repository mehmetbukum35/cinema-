import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/models/social.dart';
import 'package:ne_izlesem/screens/browse_screen.dart';
import 'package:ne_izlesem/screens/browse/browse_guest_list_card.dart';
import 'package:ne_izlesem/screens/browse/browse_top_profile_card.dart';
import 'package:ne_izlesem/screens/browse/friends_activity_teaser.dart';
import 'package:ne_izlesem/screens/browse/top_profiles_section.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs/library_facade.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/widgets/shimmer.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().hardClearAllData();
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
    expect(
      find.text('Without an account, your taste lives only on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('the rail puts the guest card before the ranked profiles', (
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
        CustomScrollView(
          slivers: [
            BrowseTopProfilesSection(
              profiles: const [],
              leadingCard: BrowseGuestListCard(preview: preview),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BrowseGuestListCard), findsOneWidget);
    // Profil yokken bile ray çizilir: davet tek başına ayakta durur.
    expect(find.byType(BrowseTopProfileCard), findsNothing);
  });

  testWidgets(
    'ranks still start at #1 after a leading card when ranked profiles exist',
    (tester) async {
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
      final profiles = [
        TopProfile(
          id: 1,
          username: 'first',
          likeCount: 10,
          meLiked: false,
          isMe: false,
          likedTitles: 5,
        ),
        TopProfile(
          id: 2,
          username: 'second',
          likeCount: 8,
          meLiked: false,
          isMe: false,
          likedTitles: 4,
        ),
      ];

      await tester.pumpWidget(
        pumpApp(
          // BrowseTopProfileCard'ın InkWell'i bir Material atası ister;
          // önceki testte olmayan bu kart burada gerçekten render olacağı
          // için Scaffold gerekiyor.
          Scaffold(
            body: CustomScrollView(
              slivers: [
                BrowseTopProfilesSection(
                  profiles: profiles,
                  leadingCard: BrowseGuestListCard(preview: preview),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BrowseGuestListCard), findsOneWidget);
      expect(find.byType(BrowseTopProfileCard), findsNWidgets(2));
      // Öncü kart sıra numarası ALMAZ: sıralanan ilk profil yine #1'dir,
      // off-by-one yok.
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    },
  );

  group('GuestListPreview.load', () {
    // Sunucunun `liked_titles` ölçütünü taklit eder: rating >= 2, gizli
    // değil. `withPoster: false` afişi eksik bir TMDB kaydını simüle eder.
    Future<void> rate(
      int id, {
      required int rating,
      int isPrivate = 0,
      bool withPoster = true,
    }) async {
      await PrefsLibraryFacade.saveRating(
        movie: Movie(
          id: id,
          title: 'Movie $id',
          overview: '',
          voteAverage: 7,
          posterPath: withPoster ? '/poster$id.jpg' : null,
        ),
        rating: rating,
        isPrivate: isPrivate,
        metadataLocale: 'tr',
      );
    }

    test('exactly 3 qualifying titles returns a non-null preview', () async {
      await rate(1, rating: 2);
      await rate(2, rating: 3);
      await rate(3, rating: 4);

      final preview = await GuestListPreview.load();

      expect(preview, isNotNull);
      expect(preview!.likedCount, 3);
      expect(preview.posters.length, 3);
    });

    test('exactly 2 qualifying titles returns null', () async {
      await rate(1, rating: 2);
      await rate(2, rating: 3);

      expect(await GuestListPreview.load(), isNull);
    });

    test('a rating below 2 does not count toward the threshold', () async {
      await rate(1, rating: 2);
      await rate(2, rating: 3);
      await rate(3, rating: 1); // eşiğin altında, sayılmaz

      expect(await GuestListPreview.load(), isNull);
    });

    test('a private rating does not count toward the threshold', () async {
      await rate(1, rating: 2);
      await rate(2, rating: 3);
      await rate(3, rating: 4, isPrivate: 1);

      expect(await GuestListPreview.load(), isNull);
    });

    test(
      '3 qualifying titles where one lacks a poster still counts fully',
      () async {
        await rate(1, rating: 2);
        await rate(2, rating: 3);
        await rate(3, rating: 4, withPoster: false);

        final preview = await GuestListPreview.load();

        expect(preview, isNotNull);
        expect(preview!.likedCount, 3);
        expect(preview.posters.length, 2);
      },
    );
  });
}
