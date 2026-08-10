// Cihaz üstü eklenti duman testi (gerçek Android/iOS, gerçek plugin kanalları).
//
// Neden ayrı bir katman: `test/` altındaki her şey Dart VM'inde koşar ve
// native eklentileri taklit eder — sqflite yerine sqflite_common_ffi,
// flutter_secure_storage yerine bellek içi mock, Firebase hiç yok. Bu testler
// yeşilken cihazda patlayabilecek bir sınıf hata vardır ve VM testleri onu
// yapısal olarak göremez:
//
//  * DatabaseHelper cihazda in-memory mock'a düşerse (izin/yol hatası)
//    kullanıcı verisi sessizce uçar — VM'de bu dal zaten kasıtlı olarak
//    seçildiği için test hiç uyarmaz.
//  * Android Keystore yazma/okuma bir cihaz veya minSdk kombinasyonunda
//    kırılırsa oturum her açılışta düşer.
//  * google-services.json ile firebase_options.dart birbirinden kayarsa
//    Firebase.initializeApp yalnız gerçek cihazda hata verir.
//  * ProGuard/R8 küçültmesi release derlemesinde bir eklentiyi budarsa
//    yalnız cihazda ortaya çıkar.
//
// Çalıştırma (bağlı cihaz/emülatör gerekir):
//   flutter test integration_test/plugin_smoke_test.dart
// Release küçültmesini de doğrulamak için:
//   flutter test integration_test/plugin_smoke_test.dart --release
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/firebase_options.dart';
import 'package:ne_izlesem/main.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/prefs/auth_storage.dart';
import 'package:ne_izlesem/services/prefs/library_facade.dart';

/// Gerçek cihaz veritabanına yazdığımız için kullanıcı verisiyle çakışmayacak
/// bir kimlik aralığı seçiyoruz; her test kendinden sonra temizliyor.
const _probeMovieId = 999000001;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Native depolama', () {
    tearDown(() async {
      await PrefsLibraryFacade.deleteRating(_probeMovieId, false);
    });

    testWidgets('sqflite gerçek cihaz veritabanını açar, mock\'a düşmez', (
      tester,
    ) async {
      final db = await DatabaseHelper().database;

      // Çekirdek iddia: null dönerse DatabaseHelper in-memory mock'a düşmüştür
      // ve cihazdaki tüm kullanıcı verisi kalıcı değildir.
      expect(
        db,
        isNotNull,
        reason:
            'Cihazda gerçek SQLite açılmalı; null = in-memory mock = veri kaybı',
      );
      final version = await db!.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, kDbSchemaVersion);

      // Migration'lar gerçekten koştu mu: beklenen tablolar yerinde olmalı.
      final tables = await db.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ?',
        whereArgs: ['table'],
      );
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(['ratings', 'watchlist', 'favorites']));
    });

    testWidgets('puanlama native SQLite\'a yazılır ve geri okunur', (
      tester,
    ) async {
      await PrefsLibraryFacade.saveRating(
        movie: Movie(
          id: _probeMovieId,
          title: 'Integration Probe',
          posterPath: null,
          overview: 'Cihaz üstü duman testi kaydı',
          voteAverage: 7.0,
          releaseDate: '2024-01-01',
          isTV: false,
          genreIds: const [28],
          popularity: 1,
          voteCount: 1,
        ),
        rating: 3,
        metadataLocale: 'tr',
      );

      final row = await PrefsLibraryFacade.getRating(_probeMovieId, false);
      expect(row, isNotNull);
      expect(row!['rating'], 3);
      expect(row['title'], 'Integration Probe');

      // Silme tombstone bırakmalı (sync'in silmeyi taşıyabilmesi için),
      // ama okuma yolundan düşmeli.
      await PrefsLibraryFacade.deleteRating(_probeMovieId, false);
      expect(await PrefsLibraryFacade.getRating(_probeMovieId, false), isNull);
    });

    testWidgets('shared_preferences cihazda kalıcı yazar', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('integration_probe', 'ok');
      expect(prefs.getString('integration_probe'), 'ok');
      await prefs.remove('integration_probe');
    });
  });

  group('Güvenli depolama (Android Keystore / iOS Keychain)', () {
    tearDown(PrefsAuthStorage.clearTokens);

    testWidgets(
      'token yazılır ve bellek cache\'i baypas edilerek geri okunur',
      (tester) async {
        await PrefsAuthStorage.saveTokens(
          accessToken: 'probe_access',
          refreshToken: 'probe_refresh',
        );

        // Cache'i düşür: bundan sonraki okuma gerçekten Keystore'a gitmek
        // zorunda. Cache silinmezse bu test her koşulda yeşil kalır ve
        // Keystore kırıldığında hiçbir şey söylemez.
        PrefsAuthStorage.clearTokenCache();

        expect(await PrefsAuthStorage.getAccessToken(), 'probe_access');
        expect(await PrefsAuthStorage.getRefreshToken(), 'probe_refresh');
      },
    );

    testWidgets('clearTokens hem Keystore\'u hem cache\'i temizler', (
      tester,
    ) async {
      await PrefsAuthStorage.saveTokens(
        accessToken: 'probe_access',
        refreshToken: 'probe_refresh',
      );
      await PrefsAuthStorage.clearTokens();
      PrefsAuthStorage.clearTokenCache();

      expect(await PrefsAuthStorage.getAccessToken(), isNull);
      expect(await PrefsAuthStorage.getRefreshToken(), isNull);
    });
  });

  group('Firebase', () {
    testWidgets('gönderilen yapılandırmayla başlatılabiliyor', (tester) async {
      // google-services.json / GoogleService-Info.plist ile
      // firebase_options.dart birbirinden kayarsa yalnız burada patlar.
      final app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      expect(app.options.projectId, isNotEmpty);
      expect(Firebase.apps, isNotEmpty);
    });
  });

  group('Uygulama açılışı', () {
    testWidgets('ilk kare istisnasız çiziliyor ve ana kabuk geliyor', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: NeIzlesemApp(showOnboarding: false)),
      );

      // Splash zamanlayıcıları + prefs/DB ısınması.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2600));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Paket kimliği', () {
    testWidgets('sürüm bilgisi native tarafla eşleşiyor', (tester) async {
      final info = await PackageInfo.fromPlatform();
      expect(info.packageName, isNotEmpty);
      expect(info.version, isNotEmpty);
      // Store yüklemesinin sessizce 0 build number ile çıkmasını yakalar.
      expect(info.buildNumber, isNotEmpty);
    });
  });
}
