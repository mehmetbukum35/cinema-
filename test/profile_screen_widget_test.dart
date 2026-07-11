import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/screens/profile_screen.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';

void main() {
  setupSecureStorageMock();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_language': 'en'});
  });

  testWidgets('ProfileScreen renders cinema identity section', (tester) async {
    await tester.pumpWidget(pumpApp(const ProfileScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final identity = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          ((w.data?.toUpperCase().contains('CINEMA') ?? false) ||
              (w.data?.toUpperCase().contains('KIMLI') ?? false) ||
              (w.data?.toUpperCase().contains('KİMLİ') ?? false)),
    );
    expect(identity, findsWidgets);
  });
}
