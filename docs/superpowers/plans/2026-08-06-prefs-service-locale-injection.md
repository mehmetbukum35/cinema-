# PrefsService Mutable Global'lerinin Kaldırılması — Implementasyon Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PrefsService`'teki dört bellek içi mutable global'i kaldır; seçili dili tüketicilere kurucu enjeksiyonuyla ulaştır.

**Architecture:** `LocaleNotifier` dilin tek sahibi olur ve `initialLocaleProvider` sayesinde senkron kurulur. `ApiService`, `RecommendationEngine` ve `NotificationService` dili `String Function()` sağlayıcısı olarak alır. `PrefsService`'in kendi okumaları açık parametreye döner. Üç performans cache'i yerinde kalır ama `resetInMemoryCaches()` ile sıfırlanabilir olur.

**Tech Stack:** Flutter 3 / Dart 3.12, Riverpod 3 (`StateNotifierProvider`, `Provider`), `shared_preferences`, `flutter_secure_storage`, `flutter_test`.

**Spec:** [2026-08-06-prefs-service-locale-injection-design.md](../specs/2026-08-06-prefs-service-locale-injection-design.md)

## Global Constraints

- Dart tarafında her commit öncesi: `dart format .` ve `flutter analyze` sıfır sorunla geçmeli.
- `analysis_options.yaml` içinde `strict-casts: true` ve `strict-raw-types: true` etkin; `dynamic` değerler açık cast ister.
- Lint `only_throw_errors` etkin: testlerde `Error` alt sınıfı fırlatma, `Exception` implement eden bir sınıf kullan.
- Yeni kullanıcıya görünen metin eklenirse hem `lib/l10n/en.dart` hem `lib/l10n/tr.dart` güncellenmeli. **Bu planda yeni metin yok.**
- Conventional Commits: `<type>(<scope>): <özet>`. Tipler: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `ci`.
- Doğrudan `main` dalına commit'lenir; dal açılmaz.
- CI eşiği: `lib/services`, `lib/providers`, `lib/models` toplam satır kapsamı ≥ %70. Plan başlangıcında %76.9.
- Testler mevcut davranışı koruduğu için ilk çalıştırmada geçer. Bu yüzden her yeni test için **mutasyon kontrolü** zorunludur: üretim kodunu testin yakaladığını iddia ettiği şekilde boz, testin düştüğünü gör, geri al.

---

### Task 1: Cache reset kancası

Üç bellek içi cache (`_cachedAccessToken`, `_cachedGenreWeights`, `_recoTelemetryTail`) testler arasında sızıyor. `resetAll()` zaten üçünü de temizliyor ama diski de siliyor; testlerin ihtiyacı olan yalnız bellek kısmı. Mevcut mantığı ayıklayıp yeniden kullanıyoruz.

**Files:**
- Modify: `lib/services/prefs_service.dart:856-864` (`resetAll`)
- Test: `test/prefs_service_test.dart`

**Interfaces:**
- Consumes: yok (ilk task)
- Produces: `PrefsService.resetInMemoryCaches()` → `void`. Sonraki task'ların testleri bunu `setUp` içinde çağırır.

- [ ] **Step 1: Failing test'i yaz**

`test/prefs_service_test.dart` dosyasının sonundaki `main()` içine ekle:

```dart
  group('PrefsService bellek içi cache', () {
    test('resetInMemoryCaches sonrası token cache yerine depolama okunur', () async {
      await PrefsService.saveTokens(
        accessToken: 'first_access',
        refreshToken: 'first_refresh',
      );
      expect(await PrefsService.getAccessToken(), 'first_access');

      // Depolamayı doğrudan boşalt: cache temizlenmezse eski token dönmeye devam eder.
      await PrefsService.clearAuthData();
      await PrefsService.saveTokens(
        accessToken: 'second_access',
        refreshToken: 'second_refresh',
      );
      PrefsService.resetInMemoryCaches();

      expect(await PrefsService.getAccessToken(), 'second_access');
    });

    test('saveTokens cache ile depolamayı ayrıştırmaz', () async {
      await PrefsService.saveTokens(
        accessToken: 'token_a',
        refreshToken: 'refresh_a',
      );
      PrefsService.resetInMemoryCaches();

      // Cache sıfırlandıktan sonra secure storage'dan okunan değer aynı olmalı.
      expect(await PrefsService.getAccessToken(), 'token_a');
    });

    test('clearAuthData cache içindeki token’ı da düşürür', () async {
      await PrefsService.saveTokens(
        accessToken: 'token_b',
        refreshToken: 'refresh_b',
      );
      expect(await PrefsService.getAccessToken(), 'token_b');

      await PrefsService.clearAuthData();

      expect(await PrefsService.getAccessToken(), isNull);
    });
  });
```

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/prefs_service_test.dart --plain-name "bellek içi cache"
```

Beklenen: derleme hatası — `The method 'resetInMemoryCaches' isn't defined for the type 'PrefsService'`.

- [ ] **Step 3: `resetInMemoryCaches` ekle ve `resetAll`'ı ona bağla**

`lib/services/prefs_service.dart` içindeki mevcut `resetAll` bloğunu:

```dart
  static Future<void> resetAll() async {
    _recoTelemetryTail = Future<void>.value();
    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = null;
    invalidateGenreWeights();
    await prefs.clear();
    await _secureStorage.deleteAll();
    await DatabaseHelper().clearAllData();
  }
```

şununla değiştir:

```dart
  /// Bellekte tutulan performans cache'lerini sıfırlar. Diske dokunmaz.
  ///
  /// Testler için gerekli: bu cache'ler statik olduğundan bir testin yazdığı
  /// token veya tür ağırlığı, aynı dosyadaki sonraki testlere sızar ve testleri
  /// çalışma sırasına bağımlı kılar.
  @visibleForTesting
  static void resetInMemoryCaches() {
    _cachedAccessToken = null;
    _recoTelemetryTail = Future<void>.value();
    invalidateGenreWeights();
  }

  static Future<void> resetAll() async {
    resetInMemoryCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.deleteAll();
    await DatabaseHelper().clearAllData();
  }
```

- [ ] **Step 4: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/prefs_service_test.dart --plain-name "bellek içi cache"
```

Beklenen: 3 test PASS.

- [ ] **Step 5: Mutasyon kontrolü**

`resetInMemoryCaches` içindeki `_cachedAccessToken = null;` satırını geçici olarak sil, testi tekrar çalıştır.

Beklenen: "resetInMemoryCaches sonrası token cache yerine depolama okunur" testi FAIL (`'first_access'` dönüyor). Gördükten sonra satırı geri koy ve testlerin tekrar geçtiğini doğrula.

- [ ] **Step 6: Doğrula ve commit'le**

```bash
dart format . && flutter analyze && flutter test test/prefs_service_test.dart
```

```bash
git add lib/services/prefs_service.dart test/prefs_service_test.dart && git commit -m "test(prefs): add resettable in-memory cache hook"
```

---

### Task 2: Senkron LocaleNotifier ve tek yazıcı

Bugün `LocaleNotifier` başlangıç durumunu platform dilinden senkron hesaplıyor ama kaydedilmiş tercihi asenkron okuyor; `activeLanguageCode` ise sabit `'tr'` ile başlıyor. Bu task yarışı kapatır ve global'in tek yazıcısını `LocaleNotifier` yapar. Global bu aşamada **hâlâ mevcut** — 9 dosya onu okumaya devam eder, uygulama çalışır.

**Files:**
- Modify: `lib/services/providers.dart:24-57` (`LocaleNotifier`, `localeProvider`)
- Modify: `lib/services/prefs_service.dart:91-95` (`setSelectedLanguage`)
- Modify: `lib/main.dart:112-113`
- Test: `test/locale_provider_test.dart` (yeni)

**Interfaces:**
- Consumes: yok
- Produces:
  - `initialLocaleProvider` → `Provider<String?>`, `providers.dart` içinde. Task 3–5 testleri bunu override eder.
  - `LocaleNotifier.setLocale(String langCode)` → `Future<void>` (imza değişmiyor)
  - `localeProvider` → `StateNotifierProvider<LocaleNotifier, Locale>` (değişmiyor)

- [ ] **Step 1: Failing test'i yaz**

`test/locale_provider_test.dart` dosyasını oluştur:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/services/prefs_service.dart';
import 'package:ne_izlesem/services/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsService.resetInMemoryCaches();
  });

  test('kaydedilmiş dil ilk okumada, await olmadan görünür', () {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('en')],
    );
    addTearDown(container.dispose);

    // Hiçbir await yok: notifier senkron kurulmalı.
    expect(container.read(localeProvider).languageCode, 'en');
  });

  test('kayıt yoksa platform diline düşülür', () {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(localeProvider).languageCode, anyOf('tr', 'en'));
  });

  test('setLocale hem durumu hem diski günceller', () async {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('tr')],
    );
    addTearDown(container.dispose);

    await container.read(localeProvider.notifier).setLocale('en');

    expect(container.read(localeProvider).languageCode, 'en');
    expect(await PrefsService.getSelectedLanguage(), 'en');
  });
}
```

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/locale_provider_test.dart
```

Beklenen: derleme hatası — `Undefined name 'initialLocaleProvider'`.

- [ ] **Step 3: `LocaleNotifier`'ı senkron hale getir**

`lib/services/providers.dart` içindeki `LocaleNotifier` sınıfını ve `localeProvider`'ı şununla değiştir:

```dart
/// Açılışta diskten okunmuş dil kodu. `main()` gerçek değerle override eder;
/// override yoksa (veya kayıt yoksa) `null` gelir ve platform diline düşülür.
/// Testler bu provider'ı override ederek dili senkron olarak sabitleyebilir.
final initialLocaleProvider = Provider<String?>((ref) => null);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(String? initialLanguageCode)
    : super(Locale(_resolve(initialLanguageCode)));

  /// Dil çözümü tek yerde: kayıtlı tercih varsa o, yoksa platform dili;
  /// desteklenmeyen her dil 'en'e düşer.
  static String _resolve(String? saved) {
    if (saved == 'tr' || saved == 'en') return saved!;
    final sysLang = ui.PlatformDispatcher.instance.locale.languageCode;
    return sysLang == 'tr' ? 'tr' : 'en';
  }

  Future<void> setLocale(String langCode) async {
    await PrefsService.setSelectedLanguage(langCode);
    state = Locale(langCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(ref.watch(initialLocaleProvider));
});
```

- [ ] **Step 4: `setSelectedLanguage`'ı yalnız kalıcılaştırmaya indir**

`lib/services/prefs_service.dart` içinde:

```dart
  static Future<void> setSelectedLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
    activeLanguageCode = lang;
  }
```

şu hale gelsin (son satır silinir):

```dart
  static Future<void> setSelectedLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
  }
```

- [ ] **Step 5: `main()`'de kaydedilmiş dili oku ve override et**

`lib/main.dart` içinde:

```dart
  final onboardingDone = await PrefsService.isOnboardingDone();
  runApp(ProviderScope(child: NeIzlesemApp(showOnboarding: !onboardingDone)));
```

şununla değiştir:

```dart
  final onboardingDone = await PrefsService.isOnboardingDone();
  final savedLanguage = await PrefsService.getSelectedLanguage();
  // Dil runApp'ten ÖNCE okunur: aksi halde ilk isteklerin Accept-Language
  // başlığı, tercih diskten gelene kadar platform diline takılır.
  PrefsService.activeLanguageCode = savedLanguage ?? 'tr';
  runApp(
    ProviderScope(
      overrides: [initialLocaleProvider.overrideWithValue(savedLanguage)],
      child: NeIzlesemApp(showOnboarding: !onboardingDone),
    ),
  );
```

`lib/main.dart` içinde `providers.dart` import'u yoksa ekle:

```dart
import 'services/providers.dart';
```

> Not: `PrefsService.activeLanguageCode` ataması **geçicidir**. Global'i hâlâ okuyan 9 dosya Task 3–7'de temizlenecek, Task 9'da bu satır ve alanın kendisi silinecek.

- [ ] **Step 6: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/locale_provider_test.dart
```

Beklenen: 3 test PASS.

- [ ] **Step 7: Mutasyon kontrolü**

`LocaleNotifier`'ın kurucusunu `LocaleNotifier(String? initialLanguageCode) : super(Locale(_resolve(null)))` yapıp (parametre yok sayılır) testi çalıştır.

Beklenen: "kaydedilmiş dil ilk okumada, await olmadan görünür" testi FAIL. Gördükten sonra geri al.

- [ ] **Step 8: Tam süiti çalıştır**

```bash
dart format . && flutter analyze && flutter test
```

Beklenen: hepsi PASS. `LocaleNotifier()` parametresiz çağıran bir test varsa derleme hatası verir; o çağrıyı `LocaleNotifier(null)` yap.

- [ ] **Step 9: Commit**

```bash
git add lib/services/providers.dart lib/services/prefs_service.dart lib/main.dart test/locale_provider_test.dart && git commit -m "refactor(locale): make LocaleNotifier synchronous and the single writer"
```

---

### Task 3: ApiService'e dil enjeksiyonu

`ApiClient` üç yerde global'i okuyor: `Accept-Language` başlığı, in-flight GET cache anahtarı ve `sync_api`'deki `?locale=` parametresi. `ApiClient`'ın kurucusu zaten opsiyonel enjeksiyon deseni kullanıyor; dördüncü parametreyi aynı desende ekliyoruz.

**Files:**
- Modify: `lib/services/api_service.dart:45-50` (`ApiClient` kurucusu), `:65` (`_getHeaders`), `:152` (in-flight anahtarı), `:358-363` (`ApiService` kurucusu)
- Modify: `lib/services/api/sync_api.dart:13`
- Modify: `lib/services/providers.dart` (`apiServiceProvider` — Task 2'de dokunulmadı, `lib/providers/auth_provider.dart:994-996`'da tanımlı)
- Test: `test/api_service_test.dart`

**Interfaces:**
- Consumes: `initialLocaleProvider`, `localeProvider` (Task 2)
- Produces: `ApiClient({..., String Function()? localeCode})`. Varsayılan `() => 'tr'`. `ApiService` bunu `super.localeCode` ile geçirir. Task 9 bu alanın global okumadığını doğrular.

- [ ] **Step 1: Failing test'i yaz**

`test/api_service_test.dart` içindeki `main()` sonuna ekle:

```dart
  group('ApiService dil enjeksiyonu', () {
    test('aynı süreçteki iki örnek farklı Accept-Language gönderir', () async {
      final sentLanguages = <String>[];
      http.Client clientRecording() => MockClient((request) async {
        sentLanguages.add(request.headers['accept-language'] ?? '<yok>');
        return http.Response('{"ok":true}', 200);
      });

      final english = ApiService(
        client: clientRecording(),
        localeCode: () => 'en',
      );
      final turkish = ApiService(
        client: clientRecording(),
        localeCode: () => 'tr',
      );

      await english.getFriends();
      await turkish.getFriends();

      expect(sentLanguages, ['en', 'tr']);
    });

    test('sağlayıcı her istekte yeniden okunur', () async {
      final sentLanguages = <String>[];
      var current = 'tr';
      final apiService = ApiService(
        client: MockClient((request) async {
          sentLanguages.add(request.headers['accept-language'] ?? '<yok>');
          return http.Response('{"ok":true}', 200);
        }),
        localeCode: () => current,
      );

      await apiService.getFriends();
      current = 'en';
      await apiService.getFriends();

      expect(sentLanguages, ['tr', 'en']);
    });
  });
```

`http` ve `MockClient` import'ları dosyada zaten var; yoksa ekle:

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
```

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/api_service_test.dart --plain-name "dil enjeksiyonu"
```

Beklenen: derleme hatası — `No named parameter with the name 'localeCode'`.

- [ ] **Step 3: `ApiClient`'a parametreyi ekle**

`lib/services/api_service.dart` içinde `ApiClient` kurucusunu:

```dart
  ApiClient({
    http.Client? client,
    this.onSessionExpired,
    this.requestTimeout = _kRequestTimeout,
    this.transientRetryDelay = const Duration(milliseconds: 250),
  }) : _client = client ?? http.Client();
```

şununla değiştir:

```dart
  /// Aktif arayüz dili. Sunucuya `Accept-Language` olarak gider ve in-flight
  /// GET birleştirme anahtarının parçasıdır. Her istekte yeniden okunur ki
  /// kullanıcı dili değiştirdiğinde eski değere takılı kalmasın.
  final String Function() localeCode;

  ApiClient({
    http.Client? client,
    this.onSessionExpired,
    this.requestTimeout = _kRequestTimeout,
    this.transientRetryDelay = const Duration(milliseconds: 250),
    String Function()? localeCode,
  }) : _client = client ?? http.Client(),
       localeCode = localeCode ?? _defaultLocaleCode;

  static String _defaultLocaleCode() => 'tr';
```

- [ ] **Step 4: Üç okuma yerini değiştir**

`lib/services/api_service.dart:65`:

```dart
      'Accept-Language': PrefsService.activeLanguageCode,
```
→
```dart
      'Accept-Language': localeCode(),
```

`lib/services/api_service.dart:152`:

```dart
    final key = (PrefsService.activeLanguageCode, authToken, path);
```
→
```dart
    final key = (localeCode(), authToken, path);
```

`lib/services/api/sync_api.dart:13` içindeki:

```dart
&locale=${Uri.encodeQueryComponent(PrefsService.activeLanguageCode)}
```
→
```dart
&locale=${Uri.encodeQueryComponent(localeCode())}
```

- [ ] **Step 5: `ApiService` kurucusunu geçirgen yap**

`lib/services/api_service.dart:358-363`:

```dart
  ApiService({
    super.client,
    super.onSessionExpired,
    super.requestTimeout,
    super.transientRetryDelay,
  });
```
→
```dart
  ApiService({
    super.client,
    super.onSessionExpired,
    super.requestTimeout,
    super.transientRetryDelay,
    super.localeCode,
  });
```

- [ ] **Step 6: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/api_service_test.dart --plain-name "dil enjeksiyonu"
```

Beklenen: 2 test PASS.

- [ ] **Step 7: Üretim bağlantısını kur ve testini yaz**

`lib/providers/auth_provider.dart:994-996`:

```dart
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});
```
→
```dart
final apiServiceProvider = Provider<ApiService>((ref) {
  // Sağlayıcı her istekte okunur; dil değişince yeni istekler yeni dili alır.
  return ApiService(localeCode: () => ref.read(localeProvider).languageCode);
});
```

`lib/providers/auth_provider.dart` içinde `services/providers.dart` import'u zaten var (satır 23). Ardından `test/locale_provider_test.dart` içine ekle:

```dart
  test('apiServiceProvider localeProvider’ı takip eder', () async {
    final container = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('en')],
    );
    addTearDown(container.dispose);

    final apiService = container.read(apiServiceProvider);
    expect(apiService.localeCode(), 'en');

    await container.read(localeProvider.notifier).setLocale('tr');
    expect(apiService.localeCode(), 'tr');
  });
```

Import ekle:

```dart
import 'package:ne_izlesem/providers/auth_provider.dart';
```

- [ ] **Step 8: Bağlantı testini çalıştır**

```bash
flutter test test/locale_provider_test.dart
```

Beklenen: 4 test PASS.

- [ ] **Step 9: Mutasyon kontrolü**

`apiServiceProvider`'daki `localeCode:` argümanını sil (`return ApiService();`), testi çalıştır.

Beklenen: "apiServiceProvider localeProvider'ı takip eder" testi FAIL (`'tr'` yerine varsayılan `'tr'` dönerken ilk `expect` `'en'` bekliyor). Gördükten sonra geri al.

- [ ] **Step 10: Doğrula ve commit'le**

```bash
dart format . && flutter analyze && flutter test
```

```bash
git add lib/services/api_service.dart lib/services/api/sync_api.dart lib/providers/auth_provider.dart test/api_service_test.dart test/locale_provider_test.dart && git commit -m "refactor(api): inject locale into ApiClient instead of reading a global"
```

---

### Task 4: RecommendationEngine'e dil enjeksiyonu

Motor tek yerde global'i okuyor: kültürel "ev" bölgelerini çözerken.

**Files:**
- Modify: `lib/services/recommendation_engine.dart:36-38` (kurucu), `:751`
- Modify: `lib/services/providers.dart:130-132` (`recommendationEngineProvider`)
- Test: `test/recommendation_engine_test.dart`

**Interfaces:**
- Consumes: `localeProvider` (Task 2)
- Produces: `RecommendationEngine(TmdbService service, {String Function()? localeCode})`. Varsayılan `() => 'tr'`.

- [ ] **Step 1: Failing test'i yaz**

`test/recommendation_engine_test.dart` içindeki `main()` sonuna ekle:

```dart
  group('RecommendationEngine dil enjeksiyonu', () {
    test('kurucuda verilen dil kaynağı okunur', () {
      final engine = RecommendationEngine(
        TmdbService(client: MockClient((_) async => http.Response('{}', 200))),
        localeCode: () => 'en',
      );

      expect(engine.localeCode(), 'en');
    });

    test('dil kaynağı verilmezse tr varsayılır', () {
      final engine = RecommendationEngine(
        TmdbService(client: MockClient((_) async => http.Response('{}', 200))),
      );

      expect(engine.localeCode(), 'tr');
    });
  });
```

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/recommendation_engine_test.dart --plain-name "dil enjeksiyonu"
```

Beklenen: derleme hatası — `No named parameter with the name 'localeCode'`.

- [ ] **Step 3: Kurucuyu değiştir**

`lib/services/recommendation_engine.dart`:

```dart
class RecommendationEngine {
  final TmdbService _service;

  RecommendationEngine(this._service);
```
→
```dart
class RecommendationEngine {
  final TmdbService _service;

  /// Aktif arayüz dili. Kültürel "ev bölgesi" çözümü buna bakar; kullanıcı
  /// dili değiştirdiğinde sonraki sıralama yeni dile göre yapılır.
  final String Function() localeCode;

  RecommendationEngine(this._service, {String Function()? localeCode})
    : localeCode = localeCode ?? _defaultLocaleCode;

  static String _defaultLocaleCode() => 'tr';
```

- [ ] **Step 4: Okuma yerini değiştir**

`lib/services/recommendation_engine.dart:751`:

```dart
      languageCode: PrefsService.activeLanguageCode,
```
→
```dart
      languageCode: localeCode(),
```

- [ ] **Step 5: Üretim bağlantısını kur**

`lib/services/providers.dart:130-132`:

```dart
final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return RecommendationEngine(ref.watch(tmdbServiceProvider));
});
```
→
```dart
final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return RecommendationEngine(
    ref.watch(tmdbServiceProvider),
    localeCode: () => ref.read(localeProvider).languageCode,
  );
});
```

- [ ] **Step 6: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/recommendation_engine_test.dart --plain-name "dil enjeksiyonu"
```

Beklenen: 2 test PASS.

- [ ] **Step 7: Mutasyon kontrolü**

Kurucudaki `localeCode = localeCode ?? _defaultLocaleCode` ifadesini `localeCode = _defaultLocaleCode` yap, testi çalıştır.

Beklenen: "kurucuda verilen dil kaynağı okunur" testi FAIL. Gördükten sonra geri al.

- [ ] **Step 8: Doğrula ve commit'le**

```bash
dart format . && flutter analyze && flutter test
```

```bash
git add lib/services/recommendation_engine.dart lib/services/providers.dart test/recommendation_engine_test.dart && git commit -m "refactor(recommendation): inject locale into RecommendationEngine"
```

---

### Task 5: NotificationService'e dil kaynağı

`NotificationService.instance` süreç ömrü boyunca yaşayan bir singleton; `ProviderContainer` gelip geçer. Doğrudan `ref.read` closure'ı verilirse container dispose edildikten sonra ölü ref tutar. Çözüm, `AuthNotifier`'ın `setAuthReadyHandler` için zaten uyguladığı kur/temizle deseninin aynısıdır.

İki `static` getter (`_localizedSocialChannel`, `_localizedReleaseChannel`) instance alanı okuyamaz; altı kullanım yerinin hepsi instance metodunun içinde olduğundan bunlar instance getter'a çevrilir.

**Files:**
- Modify: `lib/services/notification_service.dart:110-131` (iki static getter), `:465`, `:743`, `:364` civarı (`setAuthReadyHandler` komşuluğu)
- Modify: `lib/providers/auth_provider.dart:83-91` (kurucu), `:208-215` (`dispose`)
- Test: `test/notification_routing_test.dart`

**Interfaces:**
- Consumes: `localeProvider` (Task 2)
- Produces: `NotificationService.setLocaleSource(String Function()? source)` → `void`. `null` verilirse `'tr'` varsayılanına döner. `NotificationService.localeCode` → `String` (getter).

- [ ] **Step 1: Failing test'i yaz**

`test/notification_routing_test.dart` içindeki `main()` sonuna ekle:

```dart
  group('NotificationService dil kaynağı', () {
    tearDown(() {
      NotificationService.instance.setLocaleSource(null);
    });

    test('kaynak kurulduğunda o dili döndürür', () {
      NotificationService.instance.setLocaleSource(() => 'en');

      expect(NotificationService.instance.localeCode, 'en');
    });

    test('kaynak null’landığında varsayılana düşer, hata atmaz', () {
      NotificationService.instance.setLocaleSource(() => 'en');
      NotificationService.instance.setLocaleSource(null);

      expect(NotificationService.instance.localeCode, 'tr');
    });

    test('AuthNotifier dispose edildikten sonra kaynak temizlenir', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [initialLocaleProvider.overrideWithValue('en')],
      );
      container.read(authProvider.notifier);
      await pumpEventQueue();
      expect(NotificationService.instance.localeCode, 'en');

      container.dispose();

      // Ölü container'a düşmemeli: varsayılana dönmüş olmalı.
      expect(NotificationService.instance.localeCode, 'tr');
    });
  });
```

Gereken import'lar (dosyada yoksa ekle):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/services/providers.dart';
```

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/notification_routing_test.dart --plain-name "dil kaynağı"
```

Beklenen: derleme hatası — `The method 'setLocaleSource' isn't defined`.

- [ ] **Step 3: `setLocaleSource` ve `localeCode` ekle**

`lib/services/notification_service.dart` içinde, mevcut `setAuthReadyHandler` metodunun hemen altına ekle:

```dart
  Future<void> Function()? _authReadyHandler;
  String Function()? _localeSource;

  /// Aktif arayüz dilini okuyan kaynak. `AuthNotifier` kurulurken verir,
  /// dispose olurken `null`'lar — bu servis singleton olduğu için ölü bir
  /// `ProviderContainer`'a bağlı kalmamalı.
  void setLocaleSource(String Function()? source) {
    _localeSource = source;
  }

  /// Kaynak yoksa (uygulama henüz kurulmadıysa veya container düştüyse)
  /// varsayılan dile düşer; bildirim metni hiçbir koşulda patlamaz.
  String get localeCode => _localeSource?.call() ?? 'tr';
```

> `_authReadyHandler` alanı dosyada **zaten** `:53` civarında tanımlı. Yukarıdaki blokta yalnızca `_localeSource` alanını, `setLocaleSource` metodunu ve `localeCode` getter'ını ekle; `_authReadyHandler` satırını tekrar ekleme.

- [ ] **Step 4: İki static getter'ı instance getter'a çevir**

`lib/services/notification_service.dart:110` ve `:122`:

```dart
  static AndroidNotificationChannel get _localizedSocialChannel {
    final tr = PrefsService.activeLanguageCode == 'tr';
```
→
```dart
  AndroidNotificationChannel get _localizedSocialChannel {
    final tr = localeCode == 'tr';
```

```dart
  static AndroidNotificationChannel get _localizedReleaseChannel {
    final tr = PrefsService.activeLanguageCode == 'tr';
```
→
```dart
  AndroidNotificationChannel get _localizedReleaseChannel {
    final tr = localeCode == 'tr';
```

Altı kullanım yeri (`:177`, `:178`, `:421-423`, `:484-486`) instance metodunun içinde olduğundan değişmez.

- [ ] **Step 5: Kalan iki okumayı değiştir**

`lib/services/notification_service.dart:465`:

```dart
      final tr = PrefsService.activeLanguageCode == 'tr';
```
→
```dart
      final tr = localeCode == 'tr';
```

`lib/services/notification_service.dart:743`:

```dart
    final locale = notificationContentLocale(PrefsService.activeLanguageCode);
```
→
```dart
    final locale = notificationContentLocale(localeCode);
```

- [ ] **Step 6: `AuthNotifier`'da kur ve temizle**

`lib/providers/auth_provider.dart:83-91`:

```dart
  AuthNotifier(this._apiService, this._ref) : super(AuthState()) {
    _apiService.onSessionExpired = clearSession;
    NotificationService.instance.setAuthReadyHandler(
      () => _sessionReady.future,
    );
```
→
```dart
  AuthNotifier(this._apiService, this._ref) : super(AuthState()) {
    _apiService.onSessionExpired = clearSession;
    NotificationService.instance.setAuthReadyHandler(
      () => _sessionReady.future,
    );
    NotificationService.instance.setLocaleSource(
      () => _ref.read(localeProvider).languageCode,
    );
```

`lib/providers/auth_provider.dart:208-215`:

```dart
  @override
  void dispose() {
    NotificationService.instance.setAuthReadyHandler(null);
```
→
```dart
  @override
  void dispose() {
    NotificationService.instance.setAuthReadyHandler(null);
    NotificationService.instance.setLocaleSource(null);
```

- [ ] **Step 7: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/notification_routing_test.dart --plain-name "dil kaynağı"
```

Beklenen: 3 test PASS.

- [ ] **Step 8: Mutasyon kontrolü**

`AuthNotifier.dispose()` içindeki `setLocaleSource(null);` satırını sil, testi çalıştır.

Beklenen: "AuthNotifier dispose edildikten sonra kaynak temizlenir" testi FAIL — ya `'en'` döner ya da ölü container `StateError` atar. Her iki sonuç da testin işini yaptığını gösterir. Gördükten sonra geri al.

- [ ] **Step 9: Doğrula ve commit'le**

```bash
dart format . && flutter analyze && flutter test
```

```bash
git add lib/services/notification_service.dart lib/providers/auth_provider.dart test/notification_routing_test.dart && git commit -m "refactor(notifications): take locale from an injectable source"
```

---

### Task 6: results_screen dil etiketi

`_getLanguageLabel` bir `static` metot, yani içinde `ref` veya `context` yok. Dil parametre olarak geçirilir; iki çağrı yeri widget ağacının içinde olduğundan `Localizations.localeOf(context)` kullanılabilir.

**Files:**
- Modify: `lib/screens/results_screen.dart:92-96` (`_getLanguageLabel`), `:438`, `:593`
- Test: yok (saf görüntüleme; Task 9'daki referans taraması kapsıyor)

**Interfaces:**
- Consumes: yok
- Produces: `_getLanguageLabel(String code, String fallback, String localeCode)` — dosya-içi private, dışarıdan tüketilmez.

- [ ] **Step 1: İmzayı değiştir**

`lib/screens/results_screen.dart:92-93`:

```dart
  static String _getLanguageLabel(String code, String fallback) {
    final isTr = PrefsService.activeLanguageCode == 'tr';
```
→
```dart
  static String _getLanguageLabel(
    String code,
    String fallback,
    String localeCode,
  ) {
    final isTr = localeCode == 'tr';
```

- [ ] **Step 2: İki çağrı yerini güncelle**

`lib/screens/results_screen.dart:438`:

```dart
                      label: _getLanguageLabel(l.code, l.label),
```
→
```dart
                      label: _getLanguageLabel(
                        l.code,
                        l.label,
                        Localizations.localeOf(context).languageCode,
                      ),
```

`lib/screens/results_screen.dart:593` — bu çağrı `Widget _bodyContent()`
metodunun içindedir ve o metot `_ResultsScreenState extends ConsumerState`
sınıfına aittir; `context` sınıf özelliği olarak zaten erişilebilir, parametre
taşımaya gerek yoktur:

```dart
                        _getLanguageLabel(
                          _filterLanguage!,
                          _languages
                              .firstWhere((l) => l.code == _filterLanguage)
                              .label,
                        ),
```
→
```dart
                        _getLanguageLabel(
                          _filterLanguage!,
                          _languages
                              .firstWhere((l) => l.code == _filterLanguage)
                              .label,
                          Localizations.localeOf(context).languageCode,
                        ),
```

- [ ] **Step 3: Derlemeyi ve testleri doğrula**

```bash
dart format . && flutter analyze && flutter test test/results_screen_pagination_test.dart test/responsive_screens_test.dart
```

Beklenen: analyze temiz, testler PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/results_screen.dart && git commit -m "refactor(results): pass locale into the language label helper"
```

---

### Task 7: genreName'e dil parametresi

10 çağrı, 5 dosya. Widget'lar `Localizations.localeOf(context).languageCode` kullanır; `TasteDnaPresenter` elindeki `AppLocalizations`'ın `locale` alanını kullanır (yeni parametre gerekmez).

**Files:**
- Modify: `lib/services/prefs_service.dart:78-84`
- Modify: `lib/screens/match/match_together_body.dart:148,398`
- Modify: `lib/screens/onboarding/genre_step.dart:69`
- Modify: `lib/screens/profile/widgets/stats_cards.dart:96`
- Modify: `lib/services/taste_dna_presenter.dart:220,234,236`
- Modify: `lib/widgets/wrapped_modal.dart:46,431,597`
- Test: `test/prefs_service_test.dart`

**Interfaces:**
- Consumes: yok
- Produces: `PrefsService.genreName(int id, {required String locale})` → `String`.

- [ ] **Step 1: Failing test'i yaz**

`test/prefs_service_test.dart` içine ekle:

```dart
  group('PrefsService.genreName', () {
    test('tür adı verilen dile göre çözülür', () {
      expect(PrefsService.genreName(28, locale: 'tr'), 'Aksiyon');
      expect(PrefsService.genreName(28, locale: 'en'), 'Action');
    });

    test('bilinmeyen tür id’si dile uygun yedek döndürür', () {
      expect(PrefsService.genreName(999999, locale: 'tr'), 'Bilinmeyen');
      expect(PrefsService.genreName(999999, locale: 'en'), 'Unknown');
    });
  });
```

> Beklenen değerler doğrulandı: `lib/services/prefs_service.dart:21` →
> `28: 'Aksiyon'`, `:50` → `28: 'Action'`.

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/prefs_service_test.dart --plain-name "genreName"
```

Beklenen: derleme hatası — `No named parameter with the name 'locale'`.

- [ ] **Step 3: İmzayı değiştir**

`lib/services/prefs_service.dart:78-84`:

```dart
  static String genreName(int id) {
    if (activeLanguageCode == 'tr') {
```
→
```dart
  static String genreName(int id, {required String locale}) {
    if (locale == 'tr') {
```

- [ ] **Step 4: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/prefs_service_test.dart --plain-name "genreName"
```

Beklenen: 2 test PASS.

- [ ] **Step 5: Widget çağrılarını güncelle**

Aşağıdaki her çağrıya `locale: Localizations.localeOf(context).languageCode` ekle:

- `lib/screens/match/match_together_body.dart:148` ve `:398`
- `lib/screens/onboarding/genre_step.dart:69`
- `lib/screens/profile/widgets/stats_cards.dart:96`
- `lib/widgets/wrapped_modal.dart:46`, `:431`, `:597`

Örnek dönüşüm:

```dart
              final name = PrefsService.genreName(id);
```
→
```dart
              final name = PrefsService.genreName(
                id,
                locale: Localizations.localeOf(context).languageCode,
              );
```

Bir çağrı yerinde `context` yoksa (`.map(...)` içindeki kapalı kapsamlar gibi), dili kapsam dışında bir yerel değişkene al ve onu kullan:

```dart
    final localeCode = Localizations.localeOf(context).languageCode;
    final genreNames = topGenres
        .map((id) => PrefsService.genreName(id as int, locale: localeCode))
        .toList();
```

- [ ] **Step 6: TasteDnaPresenter çağrılarını güncelle**

`TasteDnaPresenter` kurucusunda `AppLocalizations l10n` tutuyor ve `AppLocalizations`'ın `locale` alanı var. Yeni parametre eklemeden:

`lib/services/taste_dna_presenter.dart:220`, `:234`, `:236` — her `PrefsService.genreName(X)` çağrısını şuna çevir:

```dart
PrefsService.genreName(X, locale: l10n.locale.languageCode)
```

- [ ] **Step 7: Mutasyon kontrolü**

`lib/services/prefs_service.dart` içindeki `genreName` gövdesinde
`if (locale == 'tr')` koşulunu `if (true)` yap, testi çalıştır:

```bash
flutter test test/prefs_service_test.dart --plain-name "genreName"
```

Beklenen: "tür adı verilen dile göre çözülür" testi FAIL (`'Action'` yerine
`'Aksiyon'` döner). Gördükten sonra geri al.

- [ ] **Step 8: Doğrula**

```bash
dart format . && flutter analyze && flutter test
```

Beklenen: analyze temiz, tüm testler PASS. `genreName` çağıran bir test kalmışsa `locale:` ekle.

- [ ] **Step 9: Commit**

```bash
git add lib/services/prefs_service.dart lib/screens/match/match_together_body.dart lib/screens/onboarding/genre_step.dart lib/screens/profile/widgets/stats_cards.dart lib/services/taste_dna_presenter.dart lib/widgets/wrapped_modal.dart test/prefs_service_test.dart && git commit -m "refactor(prefs): pass locale explicitly into genreName"
```

---

### Task 8: metadataLocale parametreleri

Beş yazma metodu global'i `metadataLocale` olarak diske yazıyor. Bu, yanlış dil etiketiyle önbelleğe alınmış başlık metadata'sına yol açabilir. Dil çağırandan gelir.

`saveFavoriteMovies` / `saveFavoriteTvShows` `top_list_provider.dart:41-44`'te **tear-off** olarak geçiliyor; `_writeList` alanının tipi `Future<void> Function(List<Movie>)` olduğundan adlandırılmış parametre eklemek atamayı bozar. O atama closure'a çevrilir.

**Files:**
- Modify: `lib/services/prefs_service.dart:249-266` (`saveFavoriteMovies`, `saveFavoriteTvShows`), `:284-307` (`mergeFavorite*`, `_mergeFavorites`), `:464-484` (`saveRating`), `:809-813` (`addToWatchlist`)
- Modify: `lib/providers/swipe_provider.dart:293`
- Modify: `lib/providers/watchlist_provider.dart:69`
- Modify: `lib/providers/top_list_provider.dart:40-44`
- Modify: `lib/screens/movie_detail_sheet.dart:463,540,561`
- Modify: `lib/screens/onboarding_screen.dart:137,142,218`
- Test: `test/prefs_service_test.dart`, `test/top_list_provider_test.dart`, `test/recommendation_engine_test.dart`

**Interfaces:**
- Consumes: `localeProvider` (Task 2)
- Produces:
  - `PrefsService.saveRating({..., required String metadataLocale})`
  - `PrefsService.addToWatchlist(Movie movie, {required String metadataLocale})`
  - `PrefsService.saveFavoriteMovies(List<Movie> movies, {required String metadataLocale})`
  - `PrefsService.saveFavoriteTvShows(List<Movie> shows, {required String metadataLocale})`
  - `PrefsService.mergeFavoriteMovies(List<Movie> picks, {required String metadataLocale})`
  - `PrefsService.mergeFavoriteTvShows(List<Movie> picks, {required String metadataLocale})`

- [ ] **Step 1: Failing test'i yaz**

`test/prefs_service_test.dart` içine ekle:

```dart
  group('PrefsService metadataLocale', () {
    test('saveRating verilen dili kaydeder, sabit değer yazmaz', () async {
      await PrefsService.saveRating(
        movieId: 4242,
        isTV: false,
        rating: 5,
        metadataLocale: 'en',
      );

      final stored = await DatabaseHelper().getRating(4242, false);
      expect(stored?['metadata_locale'], 'en');
    });

    test('farklı dille yazılan kayıt farklı etiketlenir', () async {
      await PrefsService.saveRating(
        movieId: 4343,
        isTV: false,
        rating: 4,
        metadataLocale: 'tr',
      );

      final stored = await DatabaseHelper().getRating(4343, false);
      expect(stored?['metadata_locale'], 'tr');
    });
  });
```

> Yeni erişimciye gerek yok: `DatabaseHelper.getRating(movieId, isTV)`
> ([db_helper.dart:609](../../../lib/services/db_helper.dart)) satırın
> tamamını `Map` olarak döner ve `metadata_locale` hem gerçek SQLite yolunda
> hem bellek içi sahte yolda (`_mockRatings`, `db_helper.dart:560`) yazılır.
> `test/prefs_service_test.dart` içinde `db_helper.dart` import'u yoksa ekle.

- [ ] **Step 2: Test'i çalıştır, derlenmediğini gör**

```bash
flutter test test/prefs_service_test.dart --plain-name "metadataLocale"
```

Beklenen: derleme hatası — `Required named parameter 'metadataLocale' must be provided` veya `No named parameter`.

- [ ] **Step 3: Beş yazma metodunu değiştir**

`lib/services/prefs_service.dart` içinde, `metadataLocale: activeLanguageCode` geçen her yeri parametreye çevir:

```dart
  static Future<void> saveFavoriteMovies(
    List<Movie> movies, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().saveFavorites(
      movies,
      false,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
  }

  static Future<void> saveFavoriteTvShows(
    List<Movie> shows, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().saveFavorites(
      shows,
      true,
      metadataLocale: metadataLocale,
    );
    invalidateGenreWeights();
  }

  static Future<void> mergeFavoriteMovies(
    List<Movie> picks, {
    required String metadataLocale,
  }) => _mergeFavorites(picks, false, metadataLocale);

  static Future<void> mergeFavoriteTvShows(
    List<Movie> picks, {
    required String metadataLocale,
  }) => _mergeFavorites(picks, true, metadataLocale);

  static Future<void> _mergeFavorites(
    List<Movie> picks,
    bool isTV,
    String metadataLocale,
  ) async {
```

`_mergeFavorites` gövdesindeki `metadataLocale: activeLanguageCode,` satırını
`metadataLocale: metadataLocale,` yap.

`saveRating` imzasına ekle:

```dart
    Object? isPrivate = DatabaseHelper.unset,
    required String metadataLocale,
  }) async {
```

ve gövdesindeki `metadataLocale: activeLanguageCode,` satırını
`metadataLocale: metadataLocale,` yap.

`addToWatchlist`:

```dart
  static Future<void> addToWatchlist(
    Movie movie, {
    required String metadataLocale,
  }) async {
    await DatabaseHelper().addToWatchlist(
      movie,
      metadataLocale: metadataLocale,
    );
  }
```

- [ ] **Step 4: Provider çağrılarını güncelle**

`lib/providers/swipe_provider.dart:293`:

```dart
    await PrefsService.saveRating(movie: movie, rating: rating);
```
→
```dart
    await PrefsService.saveRating(
      movie: movie,
      rating: rating,
      metadataLocale: ref.read(localeProvider).languageCode,
    );
```

`lib/providers/watchlist_provider.dart:69`:

```dart
      await PrefsService.addToWatchlist(movie);
```
→
```dart
      await PrefsService.addToWatchlist(
        movie,
        metadataLocale: ref.read(localeProvider).languageCode,
      );
```

Her iki dosyada `import '../services/providers.dart';` yoksa ekle. Notifier'ın
`ref` alanının adı farklıysa (`_ref` gibi) o adı kullan.

- [ ] **Step 5: top_list_provider tear-off'unu closure'a çevir**

`lib/providers/top_list_provider.dart:40-44`:

```dart
       _writeList =
           writeList ??
           (isTV
               ? PrefsService.saveFavoriteTvShows
               : PrefsService.saveFavoriteMovies),
```
→
```dart
       _writeList =
           writeList ??
           ((List<Movie> list) => isTV
               ? PrefsService.saveFavoriteTvShows(
                   list,
                   metadataLocale: ref.read(localeProvider).languageCode,
                 )
               : PrefsService.saveFavoriteMovies(
                   list,
                   metadataLocale: ref.read(localeProvider).languageCode,
                 )),
```

`import '../services/providers.dart';` yoksa ekle. `ref` kurucu parametresi
olarak alanlara atanmadan önce kullanılamıyorsa, closure'ı `this.ref` üzerinden
kuran bir gövde başlatıcısına taşı — closure çağrı anında değerlendirileceği
için `ref`'in o an atanmış olması yeterlidir.

- [ ] **Step 6: Ekran çağrılarını güncelle**

`lib/screens/movie_detail_sheet.dart:463`, `:540`, `:561` — her `PrefsService.saveRating(` çağrısına ekle:

```dart
      metadataLocale: Localizations.localeOf(context).languageCode,
```

`lib/screens/onboarding_screen.dart:137`, `:142`:

```dart
      await PrefsService.mergeFavoriteMovies(_favMovies);
      await PrefsService.mergeFavoriteTvShows(_favTvShows);
```
→
```dart
      await PrefsService.mergeFavoriteMovies(
        _favMovies,
        metadataLocale: Localizations.localeOf(context).languageCode,
      );
      await PrefsService.mergeFavoriteTvShows(
        _favTvShows,
        metadataLocale: Localizations.localeOf(context).languageCode,
      );
```

`lib/screens/onboarding_screen.dart:218` — `saveRating` çağrısına aynı
`metadataLocale:` argümanını ekle.

> `async` bir metodun içinde `await`'ten sonra `context` kullanılıyorsa,
> `Localizations.localeOf(context).languageCode` değerini **ilk `await`'ten
> önce** bir yerel değişkene al ve onu geçir. Aksi halde `use_build_context_synchronously`
> lint'i tetiklenir ve `flutter analyze` kırmızıya döner.

- [ ] **Step 7: Mevcut testlerdeki 12 çağrıyı güncelle**

`test/prefs_service_test.dart`, `test/recommendation_engine_test.dart` ve
`test/top_list_provider_test.dart` içindeki her `PrefsService.saveFavoriteMovies(...)`
ve `saveFavoriteTvShows(...)` çağrısına `metadataLocale: 'tr'` ekle. Örnek:

```dart
        await PrefsService.saveFavoriteMovies([favoriteMovie]);
```
→
```dart
        await PrefsService.saveFavoriteMovies(
          [favoriteMovie],
          metadataLocale: 'tr',
        );
```

Tam listeyi bulmak için:

```bash
grep -rn "saveFavoriteMovies\|saveFavoriteTvShows\|saveRating(\|addToWatchlist(\|mergeFavorite" test --include=*.dart
```

- [ ] **Step 8: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/prefs_service_test.dart test/top_list_provider_test.dart test/recommendation_engine_test.dart
```

Beklenen: hepsi PASS.

- [ ] **Step 9: Mutasyon kontrolü**

`saveRating` gövdesindeki `metadataLocale: metadataLocale,` satırını
`metadataLocale: 'tr',` yap, testi çalıştır.

Beklenen: "saveRating verilen dili kaydeder, sabit değer yazmaz" testi FAIL.
Gördükten sonra geri al.

- [ ] **Step 10: Doğrula ve commit'le**

```bash
dart format . && flutter analyze && flutter test
```

```bash
git add -A && git commit -m "refactor(prefs): pass metadata locale explicitly into write paths"
```

---

### Task 9: Global'i sil ve doğrula

Bu noktada `activeLanguageCode`'un tek yazıcısı `main.dart`'taki geçici satır; okuyanların hepsi temizlendi. Alan silinir ve global'in gerçekten gittiği **davranışsal** olarak doğrulanır.

**Files:**
- Modify: `lib/services/prefs_service.dart:18`
- Modify: `lib/main.dart` (Task 2'de eklenen geçici atama satırı)
- Test: `test/locale_provider_test.dart`

**Interfaces:**
- Consumes: Task 2–8'in tamamı
- Produces: yok (kapanış task'ı)

- [ ] **Step 1: Kalan referansları listele**

```bash
grep -rn "activeLanguageCode" lib test --include=*.dart
```

Beklenen: yalnız iki satır — `prefs_service.dart:18` (tanım) ve `main.dart`
(Task 2'de eklenen geçici atama). Başka bir şey çıkarsa önce onu ilgili
task'ın desenine göre temizle.

- [ ] **Step 2: "Global yok" testini yaz**

`test/locale_provider_test.dart` içine ekle:

```dart
  test('iki container aynı anda farklı dilleri taşır', () {
    final english = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('en')],
    );
    addTearDown(english.dispose);
    final turkish = ProviderContainer(
      overrides: [initialLocaleProvider.overrideWithValue('tr')],
    );
    addTearDown(turkish.dispose);

    // Paylaşılan bir global olsaydı ikisi de aynı değeri verirdi.
    expect(english.read(apiServiceProvider).localeCode(), 'en');
    expect(turkish.read(apiServiceProvider).localeCode(), 'tr');
    expect(english.read(localeProvider).languageCode, 'en');
    expect(turkish.read(localeProvider).languageCode, 'tr');
  });
```

- [ ] **Step 3: Test'i çalıştır, geçtiğini gör**

```bash
flutter test test/locale_provider_test.dart
```

Beklenen: hepsi PASS. Geçmiyorsa bir tüketici hâlâ global okuyor demektir —
Step 1'e dön.

- [ ] **Step 4: Global'i sil**

`lib/services/prefs_service.dart:18`'deki satırı sil:

```dart
  static String activeLanguageCode = 'tr';
```

`lib/main.dart`'taki geçici atamayı ve yorumunu sil:

```dart
  // Dil runApp'ten ÖNCE okunur: aksi halde ilk isteklerin Accept-Language
  // başlığı, tercih diskten gelene kadar platform diline takılır.
  PrefsService.activeLanguageCode = savedLanguage ?? 'tr';
```

`savedLanguage` değişkeni `initialLocaleProvider` override'ında kullanılmaya
devam ettiği için **kalır**.

- [ ] **Step 5: Silmenin derlemeyi bozmadığını doğrula**

```bash
flutter analyze
```

Beklenen: `No issues found!`. Herhangi bir `activeLanguageCode` hatası
çıkarsa, o çağrıyı ilgili task'ın desenine göre düzelt.

- [ ] **Step 6: Cache reset'ini test setUp'larına ekle**

Statik cache'lerden etkilenen test dosyalarının `setUp`'ına ekle:

```dart
    PrefsService.resetInMemoryCaches();
```

En az şu dosyalar: `test/prefs_service_test.dart`, `test/auth_provider_test.dart`,
`test/api_service_test.dart`, `test/sync_service_test.dart`,
`test/recommendation_engine_test.dart`.

- [ ] **Step 7: Tam süiti çalıştır ve düşenleri incele**

```bash
flutter test
```

**Bu adımda test düşmesi beklenen bir sonuçtur, arıza değil.** Cache
temizliği, bugüne kadar sızıntı sayesinde geçen bir testin gizli sıra
bağımlılığını ortaya çıkarır. Her düşen test için:

1. Testin hangi bellek durumuna örtük bağımlı olduğunu tespit et.
2. O durumu testin kendi içinde açıkça kur (örneğin gereken token'ı
   `saveTokens` ile yaz).
3. `resetInMemoryCaches()` çağrısını **kaldırma** — bağımlılığı testte düzelt.

- [ ] **Step 8: Kapsamı ölç**

```bash
flutter test --coverage
```

Ardından CI eşiğini yerelde doğrula:

```bash
awk '/^SF:/{f=$0;sub(/^SF:/,"",f);gsub(/\\/,"/",f);k=(f ~ /lib\/(services|providers|models)\//)} /^LF:/{if(k){split($0,a,":");lf+=a[2]}} /^LH:/{if(k){split($0,a,":");lh+=a[2]}} END{printf "%d/%d (%d%%)\n",lh,lf,int(lh*100/lf)}' coverage/lcov.info
```

Beklenen: ≥ %70 (plan başlangıcında %76.9). Altına düştüyse, hangi dosyanın
kapsamının azaldığını bul ve o davranış için test ekle.

- [ ] **Step 9: Son doğrulama ve commit**

```bash
dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test
```

Üçünün de temiz geçtiğini gördükten sonra:

```bash
git add -A && git commit -m "refactor(prefs): remove the activeLanguageCode global"
```

- [ ] **Step 10: Spec'i kapat**

`docs/superpowers/specs/2026-08-06-prefs-service-locale-injection-design.md`
dosyasının başındaki durum satırını güncelle:

```markdown
**Durum:** Uygulandı (2026-08-06)
```

```bash
git add docs/superpowers/specs/2026-08-06-prefs-service-locale-injection-design.md && git commit -m "docs(specs): mark locale injection design as implemented"
```

---

## Kapsam dışı

Spec'te bilinçli olarak ertelenenler — bu planda **yer almaz**:

- Android bildirim kanal adlarının dil değişiminde eskimesi (bugün de var, regresyon değil)
- `PrefsService`'in 14 alana bölünmesi ve 124 saf statik metodun DI'a alınması
- Google/Apple oturum statiklerinin enjekte edilebilir hale getirilmesi
