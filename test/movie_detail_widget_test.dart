import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/screens/movie_detail_sheet.dart';
import 'package:ne_izlesem/services/prefs/taste_prefs.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  setupSecureStorageMock();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.resetAll();
  });

  testWidgets('MovieDetailSheet renders movie title', (tester) async {
    const title = 'Widget Test Movie';
    final movie = Movie(
      id: 42,
      title: title,
      overview: 'Overview for widget test.',
      voteAverage: 8.1,
      releaseDate: '2024-06-01',
    );
    final service = detailTmdbService(title: title);

    await tester.pumpWidget(
      pumpApp(MovieDetailSheet(movie: movie, service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(title), findsWidgets);
  });

  testWidgets(
    'SynergyBadge renders bolt icon and match text when personalizedMatchScore is present (EN)',
    (tester) async {
      final movie = Movie(
        id: 42,
        title: 'Test Movie',
        overview: 'Overview',
        voteAverage: 8.0,
      )..personalizedMatchScore = 85;

      final service = detailTmdbService(title: 'Test Movie');

      await tester.pumpWidget(
        pumpApp(MovieDetailSheet(movie: movie, service: service)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Match'), findsOneWidget);
    },
  );

  testWidgets(
    'SynergyBadge renders star icon and rating text when personalizedMatchScore is null (EN)',
    (tester) async {
      final movie = Movie(
        id: 42,
        title: 'Test Movie',
        overview: 'Overview',
        voteAverage: 7.5,
      );

      final service = detailTmdbService(title: 'Test Movie');

      await tester.pumpWidget(
        pumpApp(MovieDetailSheet(movie: movie, service: service)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Rating: 7.5'), findsOneWidget);
    },
  );

  testWidgets('SynergyBadge renders star icon and rating text in TR locale', (
    tester,
  ) async {
    final movie = Movie(
      id: 42,
      title: 'Test Movie',
      overview: 'Overview',
      voteAverage: 7.5,
    );

    final service = detailTmdbService(title: 'Test Movie');

    await tester.pumpWidget(
      pumpApp(
        MovieDetailSheet(movie: movie, service: service),
        locale: const Locale('tr', 'TR'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Puan: 7.5'), findsOneWidget);
  });

  testWidgets('yeniden puanlama isabet telemetrisini iki kez yazmaz', (
    tester,
  ) async {
    // Tek gösterim yazılmış bir öneri: önce İyi (2), sonra Harika (3).
    // İkisi de `liked` yazsaydı oran 2/1 olurdu; ekran önce eskisini geri
    // almalı (`liked <= shown`).
    // Puan yazımı gerçek sqflite I/O'suna dokunuyor; testWidgets'ın sahte
    // zamanı onu asla tamamlamaz, o yüzden dokunuşlar `runAsync` içinde.
    await tester.runAsync(() => PrefsTastePrefs.recordRecoShown(['discover']));

    final movie = Movie(
      id: 42,
      title: 'Reco Movie',
      overview: 'Overview',
      voteAverage: 7.5,
    )..recoSource = 'discover';

    await tester.pumpWidget(
      pumpApp(
        // Puanlandıktan sonra yorum alanı (TextField) açılıyor; Material
        // ata gerekiyor.
        Scaffold(
          body: MovieDetailSheet(
            movie: movie,
            service: detailTmdbService(title: 'Reco Movie'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> tapRating(String label) async {
      final button = find.text(label);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(button);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<Map<String, int>?> telemetry() async =>
        (await tester.runAsync(PrefsTastePrefs.getRecoTelemetry))?['discover'];

    await tapRating('Good 👍');
    expect((await telemetry())?['liked'], 1);

    // 2 → 3: ikinci isabet tek gösterime iki kredi yazmamalı.
    await tapRating('Amazing 🌟');
    expect((await telemetry())?['shown'], 1);
    expect((await telemetry())?['liked'], 1);

    // 3 → 1 (Eh): geri çekilen beğeninin kredisi kaynakta kalmamalı.
    await tapRating('Meh 😐');
    expect((await telemetry())?['shown'], 1);
    expect((await telemetry())?['liked'], 0);
  });

  responsiveTestWidgets(
    'rating details dialog remains responsive',
    (testCase) {
      final movie = Movie(
        id: 42,
        title: 'Test Movie',
        overview: 'Overview',
        voteAverage: 7.1,
      );
      final service = detailTmdbService(title: 'Test Movie');
      return pumpApp(
        MovieDetailSheet(movie: movie, service: service),
        locale: testCase.locale,
        mediaQueryData: testCase.mediaQueryData,
      );
    },
    verify: (tester, testCase) async {
      await tester.pumpAndSettle();
      expectNoResponsiveLayoutException(
        tester,
        stage: '${testCase.name} before opening rating dialog',
      );

      final badge = testCase.locale.languageCode == 'tr'
          ? find.text('Puan: 7.1')
          : find.text('Rating: 7.1');
      await tester.tap(badge);
      await tester.pumpAndSettle();

      expect(
        find.text(
          testCase.locale.languageCode == 'tr'
              ? 'Puan Detayları'
              : 'Rating Details',
        ),
        findsOneWidget,
      );
    },
  );
}
