# PrefsService: mutable global'leri kaldır, dili enjekte et

**Tarih:** 2026-08-06
**Durum:** Tasarım onaylandı, implementasyon planı bekliyor

## Sorun

`PrefsService` 1097 satır, 124 statik metot ve 14 ayrı alan (tema, onboarding,
türler, favoriler, telemetri, puanlar, izleme geçmişi, auth/sync, DNA cache…)
içeriyor. Ancak asıl sorun statiklik değil: SharedPreferences okuyup yazan saf
statik fonksiyonlar test edilebiliyor, mevcut testler bunu kanıtlıyor.

Test izolasyonunu ve çalışma zamanını bozan şey bellekte yaşayan dört mutable
global:

| Alan | Ne | Nerede okunuyor |
|---|---|---|
| `activeLanguageCode` | seçili dilin kopyası | 9 dosya: `Accept-Language`, `/sync?locale=`, bildirim metinleri, TMDB metadata dili, `results_screen` |
| `_cachedAccessToken` | token bellek cache'i | her HTTP isteği |
| `_cachedGenreWeights` | tür ağırlığı cache'i | öneri motoru |
| `_recoTelemetryTail` | telemetri yazma kuyruğu | öneri telemetrisi |

`activeLanguageCode` iki yerden yazılıyor — `LocaleNotifier` ve
`PrefsService.setSelectedLanguage`. İkisi ayrışırsa kullanıcı Türkçe arayüzde
İngilizce bildirim alır. Aynı sınıftaki sızıntı ailesi geçmişte
`5153478 fix(personalization): seal culture preference leaks` commit'ini
doğurdu.

Ayrıca `activeLanguageCode` sabit `'tr'` ile başlıyor, oysa `LocaleNotifier`
başlangıç durumunu platform dilinden hesaplıyor. İngilizce cihazlarda açılıştaki
ilk isteklerin `Accept-Language` başlığı yanlış gidiyor.

## Kapsam

**Dahil:** yalnız dört mutable global.

**Hariç:** 124 saf statik metot olduğu gibi kalıyor. `PrefsService`'in 14 alana
bölünmesi bilinçli olarak ertelendi.

## Yaklaşım

Dil, tüketicilere kurucu üzerinden geçirilen bir `String Function()`
sağlayıcısıyla ulaşır. `ApiClient` zaten bu deseni kullanıyor (`client`,
`onSessionExpired`, `requestTimeout` hepsi opsiyonel enjeksiyon), yani yeni bir
soyutlama getirmiyoruz.

Değerlendirilip elenen alternatifler:

- **`AppLocale` tutucu nesnesi** — global'den iyi ama hâlâ paylaşılan mutable
  durum; "kim yazdı" sorusu geri gelir.
- **Servislere `Ref` geçmek** — `NotificationService` singleton olduğu için ona
  `Ref` taşımak gerekir; `Ref` servis katmanına yayılır ve testte tam bir
  `ProviderContainer` kurmadan hiçbir servis çalıştırılamaz.

## Mimari

### Dil sahipliği

`LocaleNotifier` ([lib/services/providers.dart](../../../lib/services/providers.dart))
tek sahip olur. `state` tek gerçek kaynaktır; `setLocale()` hem
`PrefsService.setSelectedLanguage()` ile diske yazar hem state'i günceller.

`PrefsService.activeLanguageCode` silinir. `setSelectedLanguage()` yalnız
kalıcılaştırma işini yapar.

### Enjeksiyon noktaları

| Tüketici | Nasıl alır | Okuma sayısı |
|---|---|---|
| `ApiClient` / `ApiService` | kurucu paramı `String Function() localeCode` | 3 |
| `NotificationService` | `setLocaleSource()`, çağıran `AuthNotifier` | 4 |
| `RecommendationEngine` | kurucu paramı | 1 |
| `results_screen` | `ref.watch(localeProvider)` | 1 |

`NotificationService`'in kaynağını `AuthNotifier` kurar; o zaten `_ref` tutuyor
ve `setAuthReadyHandler` için aynı kur/temizle döngüsünü uyguluyor.

### Yeni provider: `initialLocaleProvider`

`LocaleNotifier`'ı senkron hale getirmek için `providers.dart`'a bir provider
eklenir:

```dart
/// Açılışta diskten okunmuş dil. `main()` override eder; null ise
/// LocaleNotifier platform diline düşer. Testler doğrudan override edebilir.
final initialLocaleProvider = Provider<String?>((ref) => null);
```

`LocaleNotifier` bunu kurucuda okur ve durumunu senkron kurar; bugünkü async
`_init()` kaldırılır.

Bağlantı `providers.dart`'ta kurulur:

```dart
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(localeCode: () => ref.read(localeProvider).languageCode);
});
```

`NotificationService`'teki `_localizedSocialChannel` ve
`_localizedReleaseChannel` statik getter'dır; statik üye instance alanı
okuyamaz. Altı kullanım yerinin hepsi instance metodunun içinde olduğundan
ikisini instance getter'a çevirmek mekanik bir iştir.

### PrefsService'in kendi okumaları

Global kalkınca `PrefsService`'in içindeki altı okuma açık parametreye döner:

| Metot | Değişiklik | Çağrı |
|---|---|---|
| `genreName(int id)` | `{required String locale}` | 10 çağrı / 5 dosya |
| `saveRating(...)` | `{required String metadataLocale}` | 5 çağrı / 3 dosya |
| `addToWatchlist(...)` | aynı | 1 çağrı |
| `mergeFavoriteMovies` / `mergeFavoriteTvShows` | aynı | 2 çağrı |
| `saveFavoriteMovies` / `saveFavoriteTvShows` | aynı | 1 üretim + 12 test çağrısı |

`saveFavoriteMovies` / `saveFavoriteTvShows` ölü kod **değildir**:
[top_list_provider.dart:43](../../../lib/providers/top_list_provider.dart)
bunları tear-off olarak geçiyor. `_writeList` alanının tipi
`Future<void> Function(List<Movie>)` olduğundan, adlandırılmış parametre eklemek
tear-off atamasını bozar; o atama closure'a çevrilir ve dil oradan geçirilir.

### Cache reset kancası

`PrefsService.resetInMemoryCaches()` — `@visibleForTesting`, üç cache'i
temizler. Testlerin `setUp`'ında çağrılır. Bu üçü paylaşılan durum değil
performans cache'i olduğundan enjekte edilmez; ilaç yaşam döngüsü disiplinidir.

## Veri akışı

### Açılış

[main.dart:112](../../../lib/main.dart) zaten `runApp`'ten önce prefs okuyor.
Dili de aynı yere ekliyoruz ve `ProviderScope` override'ı ile besliyoruz:

```dart
final savedLang = await PrefsService.getSelectedLanguage(); // String?
runApp(ProviderScope(
  overrides: [initialLocaleProvider.overrideWithValue(savedLang)],
  child: NeIzlesemApp(showOnboarding: !onboardingDone),
));
```

`getSelectedLanguage()` `String?` döner; kayıt yoksa `null` geçilir ve
`LocaleNotifier` platform diline düşer — bugünkü davranışın aynısı, farkı
senkron olması.

Kazanç iki katmanlı: yanlış dil penceresi tamamen kapanır **ve**
`LocaleNotifier` senkron hale gelir — `_init()`'in async yarışı ortadan
kalktığı için notifier testte `pumpEventQueue` beklemeden doğrulanabilir.

### Dil değişimi

`setLocale()`: diske yaz → `state` güncelle → sağlayıcıyı okuyan herkes bir
sonraki çağrıda yeni değeri görür. Ek invalidasyon gerekmez:

- `ApiClient._inFlightGets` anahtarı zaten `(locale, token, path)` üçlüsü
- SQLite'taki TMDB metadata'sı zaten `metadataLocale` ile etiketli
- `_cachedGenreWeights` tür id'leri üzerinden hesaplanır, dilden bağımsız

### Yaşam döngüsü

`NotificationService.instance` süreç ömrü boyunca yaşayan bir singleton;
`ProviderContainer` gelip geçer. Ona doğrudan `ref.read` closure'ı verilirse,
container dispose edildikten sonra singleton ölü bir ref tutar ve bir sonraki
bildirim yolunda `StateError` atar.

Çözüm kodda zaten var olan desendir: `AuthNotifier`, `setAuthReadyHandler`'ı
kurucuda kurar ve `dispose()`'ta null'lar
([auth_provider.dart:85](../../../lib/providers/auth_provider.dart) ve
[:210](../../../lib/providers/auth_provider.dart)). Simetrik olarak:

```dart
NotificationService.instance.setLocaleSource(
  () => _ref.read(localeProvider).languageCode,
);
// dispose(): setLocaleSource(null);
```

Kaynak `null` iken servis kendi varsayılanına (`'tr'`) düşer.

`ApiService` ve `RecommendationEngine` için bu risk yoktur; ikisi de provider
ömrüne bağlıdır.

### Hata yönetimi

Sağlayıcı çağrısı yalnızca `Locale` okur; atacağı tek hata dispose edilmiş
container'dan gelir ve yukarıdaki null'lama bunu kapatır. Ek try/catch
eklenmez — sessizce yutulan hata bu projede zaten işaretlenmiş bir sorundur.

## Enjeksiyon zorunlu değil, varsayılanlı

`ApiService` 10 test dosyasında 26 yerde, `RecommendationEngine` 14 yerde
kuruluyor. `localeCode`'u zorunlu yapmak, dil umurunda olmayan ~40 test
satırını sırf derlensin diye değiştirmek demek.

Karar: **opsiyonel, varsayılanı `() => 'tr'`**. "Üretim bağlantısını kurmayı
unutma" riski aşağıdaki 3 numaralı testle kapatılır.

## Testler

Her test, yakaladığı kırılmayla birlikte:

**Dil izolasyonu**

1. Aynı süreçte iki `ApiService` — biri `() => 'en'`, biri `() => 'tr'` — farklı
   `Accept-Language` gönderir.
   *Kırılma:* global geri gelirse ikisi aynı değeri gönderir. Bu, "global yok"
   iddiasının davranışsal kanıtıdır; kaynak metni grep'lenmez.
2. `setLocale('en')` sonrası **aynı** `ApiService` örneğinin bir sonraki isteği
   `en` gönderir.
   *Kırılma:* sağlayıcı yerine kurulum anında değer kopyalanırsa.
3. `apiServiceProvider`'dan alınan servis `localeProvider`'ı takip eder.
   *Kırılma:* üretim bağlantısı koparsa veya unutulursa.
4. `initialLocaleProvider` `'en'` ile override edilen bir container'da
   `localeProvider` **hiçbir await olmadan**, ilk okumada `en` verir.
   *Kırılma:* `LocaleNotifier` tekrar async `_init()`'e dönerse, ilk okuma
   platform diline düşer ve test yakalar. (`main()`'in override'ı gerçekten
   geçirdiği unit test kapsamı dışıdır; bu kısım `app_flow_test` seviyesinde
   ele alınır.)

**metadataLocale doğruluğu**

5. `saveRating(..., metadataLocale: 'en')` kaydı `en` etiketler; `'tr'` ile
   yazılan sonraki kayıt `tr` etiketlenir.
   *Kırılma:* parametre yok sayılıp sabit değer yazılırsa.

**Cache sızıntısı**

6. `resetInMemoryCaches()` sonrası `getAccessToken()` secure storage'dan taze
   okur, önceki testin token'ını döndürmez.
   *Kırılma:* reset `_cachedAccessToken`'ı atlarsa.
7. `saveTokens()` cache'i günceller, `clearAuthData()` temizler; cache ile
   depolama ayrışmaz.
   *Kırılma:* `saveTokens` cache'i güncellemeyi unutursa eski token'la istek
   atılır.

**Yaşam döngüsü**

8. Container dispose edildikten sonra bildirim yolu varsayılan dile düşer,
   `StateError` atmaz.
   *Kırılma:* `dispose()`'ta `setLocaleSource(null)` unutulursa.

### Mevcut testlerde değişiklik

- `saveFavoriteMovies` / `saveFavoriteTvShows` — 12 çağrıya `metadataLocale`
  eklenir (4 dosya)
- `resetInMemoryCaches()` ilgili `setUp`'lara girer

**Risk:** cache'leri temizlemek, bugün sızıntı sayesinde geçen testleri
düşürebilir. `auth_provider_test`'e `hardClearAllData()` eklenirken aynısı
yaşandı. Düşen test arıza değil bilgidir — o testin gizli bir sıra bağımlılığı
varmış demektir. Plan buna ayrı bir adım açar.

## Doğrulama

Bu iş mevcut davranışı koruduğu için testler ilk çalıştırmada geçecek, yani
hiçbir şey kanıtlamayacak. Her testin yakaladığını iddia ettiği kırılma üretim
kodunda gerçekten oluşturulup düştüğü ölçülecek — özellikle 1, 3 ve 6.

```bash
flutter analyze && dart format --output=none --set-exit-if-changed . && flutter test --coverage
```

CI eşiği (`services|providers|models` ≥ %70) şu an %76.9. Bu iş `providers.dart`
ve `prefs_service.dart`'a test eklediğinden düşüş beklenmiyor; plan yine de
ölçüm adımı içerir.

## Kapsam dışı

- Android bildirim kanal adlarının dil değişiminde eskimesi. Bugün de var,
  regresyon değil, ayrı iş.
- `PrefsService`'in 14 alana bölünmesi ve 124 statik metodun DI'a alınması.
- Google/Apple oturum statiklerinin enjekte edilebilir hale getirilmesi
  (`auth_provider` kapsamının test edilemeyen %30'u).
