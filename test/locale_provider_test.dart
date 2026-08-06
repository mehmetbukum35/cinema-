import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsService.resetInMemoryCaches();
  });

  test('kaydedilmis dil ilk okumada, await olmadan gorunur', () {
    // Iki yon birden denenir: test ortaminin platform dili hangisi olursa
    // olsun, ikisinden en az biri parametreden gelmek ZORUNDA. Tek yon test
    // edilirse platform varsayilaniyla cakisir ve kayitli dilin yok sayildigi
    // bir regresyonu goremez.
    for (final code in ['en', 'tr']) {
      final container = ProviderContainer(
        overrides: [initialLocaleProvider.overrideWithValue(code)],
      );
      addTearDown(container.dispose);

      // Hicbir await yok: notifier senkron kurulmali. Async bir _init()'e
      // donerse ilk okuma platform diline duser ve bu test yakalar.
      expect(container.read(localeProvider).languageCode, code);
    }
  });

  test('kayit yoksa platform diline dusulur', () {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(localeProvider).languageCode, anyOf('tr', 'en'));
  });

  test('desteklenmeyen kayitli dil platform diline dusurulur', () {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('de')],
    );
    addTearDown(container.dispose);

    expect(container.read(localeProvider).languageCode, anyOf('tr', 'en'));
  });

  test('setLocale hem durumu hem diski gunceller', () async {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('tr')],
    );
    addTearDown(container.dispose);

    await container.read(localeProvider.notifier).setLocale('en');

    expect(container.read(localeProvider).languageCode, 'en');
    expect(await PrefsService.getSelectedLanguage(), 'en');
  });
}
