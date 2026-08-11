# Öneri telemetrisi ve skor kalibrasyonu

**Tarih:** 2026-08-12 · **Durum:** onaylandı, plana hazır

## Problem

Öneri motorunun iki ölçüm hatası var. İkisi de "sayı doğru mu" ekseninde ve aynı
dosyalara dokunuyor.

### 1. Cihaz-içi `shown` sayacı aslında "oylandı" demek

`PrefsRecoSignals.recordRecoOutcome` her çağrıda `shown++` yapıyor, ama yalnızca
oylama anında çağrılıyor: `lib/providers/swipe_provider.dart:356` ve
`lib/screens/movie_detail_sheet.dart:514`. Yani sayaçtaki `shown`, gösterim değil
**oylanmış** yapım sayısı. Buradan çıkan oran `P(beğeni | oylandı)`.

İki adaptif knob bu oranı `P(beğeni | gösterildi)` sanıp kullanıyor:

- `RecommendationEngine.adaptiveExploreRate` (`lib/services/recommendation_engine.dart:649`)
- Adaptif tohum sayısı (`lib/services/recommendation_engine.dart:498`)

Sonuç: kullanıcının hiç etkileşmediği adaylar üreten bir kaynak **görünmez**
kalıyor — paydaya hiç girmediği için cezalandırılamıyor. Dahası Keşfet rayı bu
sayaçlara hiç yazmıyor olmasına rağmen keşif oranı bu sayaçlardan hesaplanıyor.
`lib/services/prefs/taste/reco_signals.dart:15` yorumu da ("kaç öneri gösterilip")
gerçeği yansıtmıyor.

### 1b. Atıfsız yapımlar `discover` sayacını kirletiyor

`lib/screens/profile_screen.dart:232` ve `lib/screens/watchlist_screen.dart:368`
puan silerken `movie.recoSource ?? 'discover'` yazıyor. Ama `recoSource`
oturumluk ve kalıcı depoya yazılmıyor (`lib/models/movie.dart:118`) — kütüphaneden
gelen filmde her zaman `null`. Yani bu iki ekrandan bir puan silmek, o film hiç
öneri motorundan gelmemiş olsa bile `discover` sayacını düşürüyor.
`lib/screens/movie_detail_sheet.dart:513` aynı kuralı doğru uyguluyor
(`recoSource != null` guard'ı), diğer ikisi kaçırmış.

### 2. Gösterilen uyum yüzdesi ayırt edici değil

`RecommendationEngine.toDisplayScore` (`lib/services/recommendation_engine.dart:114`):

```dart
final z = (raw - 0.2) * 4.0;
final sigmoid = 1.0 / (1.0 + exp(-z));
return (40 + (sigmoid * 58)).round().clamp(40, 98);
```

Gerçekçi `raw` aralığı yaklaşık 0.2–0.6. Bu aralık ekranda **%69–%88**'e düşüyor;
`[40, 98]` clamp'i neredeyse hiç devreye girmiyor. Kalite farkı olan iki film
kullanıcıya %82 ve %84 olarak görünüyor. Merkez (0.2) ve eğim (×4) ölçüme
dayanmıyor, tahmin.

Ayrıca A/B'nin iki kolu farklı raw ölçekleri üretiyor: `personalization` kolu daha
ağır tür/keyword ağırlıkları ve `preferenceBoostMultiplier: 1.25` ile daha geniş
bir dağılım çıkarıyor (`lib/services/recommendation_experiment_service.dart:38`).
Tek sigmoid ikisini birden kalibre edemez.

## Hedef

1. Cihaz-içi sayacın adı ile ölçtüğü şey aynı olsun; adaptif knob'lar gerçek
   gösterim-başına dönüşüme baksın.
2. Karttaki yüzde **mutlak ve kalibre** olsun: oturumlar arası karşılaştırılabilir,
   bandı gerçekten kullanan, kötü listede gerçekten düşük yazan bir sayı.

## Hedef olmayanlar

- Analizdeki diğer 8 bulgu (recall darboğazı, kod tekrarı, jitter genliği, ...)
- Uzaktan beslenen kalibrasyon parametreleri — sabitler kodda yaşayacak
- Admin panelinde kalibrasyon görselleştirmesi; JSON rapor yeterli
- `RecommendationAnalytics::report`'un rank/slot verisini kullanacak şekilde
  genişletilmesi

## Kararlar

| Karar | Seçim |
|---|---|
| Yüzdenin anlamı | Mutlak ve kalibre |
| Kalibrasyon kaynağı | Üretimdeki `recommendation_events` verisi |
| Parametre dağıtımı | Kodda sabit, `model_version` başına |
| "Gösterildi" tanımı | Mevcut gösterim hafızası vekili (vitrin + ilk 10; swipe'ta kart) |
| Sunum ölçeği | Referans dağılımdaki yüzdelik dilim (persentil) |
| İş akışı | İki faz: önce ölçüm ucu, veri geldikten sonra sabitler |

---

## Faz 1A — Cihaz-içi telemetri semantiği

### Yeni API

`PrefsRecoSignals` (`lib/services/prefs/taste/reco_signals.dart`), public yüzey
yine `PrefsTastePrefs` üzerinden:

```dart
static Future<void> recordRecoShown(Iterable<String?> sources);  // kaynak başına shown++
static Future<void> recordRecoLiked(String? source);             // rating >= 2 ise liked++
static Future<void> revertRecoLiked(String? source);             // liked--, shown'a dokunmaz
```

`recordRecoOutcome` ve `revertRecoOutcome` kaldırılır.

**`null` guard API'nin içinde.** Üç metot da `null` kaynağı sessizce atlar —
`recordRecoShown` listedeki `null`'ları eler, diğer ikisi hiçbir şey yapmadan
döner. Üç ekranın aynı kuralı tekrar etmesi zaten 1b'deki
hataya yol açtı; kural tek yerde yaşarsa bir çağrı yerinin unutması imkânsızlaşır
ve kural unit test edilebilir hale gelir.

Yazımlar mevcut `_enqueueRecoTelemetry` kuyruğundan geçmeye devam eder.

### Anahtar sürümü

`reco_telemetry_v1` → **`reco_telemetry_v2`**. Eski veri taşınmaz: paydası farklı
bir şeyi ölçüyor, karıştırmak her iki oranı da bozar. v1 anahtarı silinir.

### Çağrı yerleri

**`shown` yazan yeni noktalar** — üçü de hâlihazırda gösterim hafızası yazan
yerler, ek altyapı gerekmiyor:

| Yer | Küme |
|---|---|
| `lib/screens/browse_screen.dart:513` | Vitrin + `finalPersonal` ilk 10 (`recordRecoImpressions` ile aynı küme) |
| `lib/screens/browse_screen.dart:638` | Vitrin yeniden çekilişi |
| `lib/screens/swipe_screen.dart:273` | Kart görünürken (kart başına bir kez) |

Kaynak `Movie.recoSource` alanından okunur; atıfsız (`null`) yapımlar API içinde
elenir.

**`liked` yazan noktalar** (yalnız `rating >= 2` iken):
`lib/providers/swipe_provider.dart:356`, `lib/screens/movie_detail_sheet.dart:514`.

**Revert noktaları** (`revertRecoLiked`, yalnız silinen puan `>= 2` iken):
`lib/providers/swipe_provider.dart:398`, `lib/screens/movie_detail_sheet.dart:477`,
`lib/screens/profile_screen.dart:232`, `lib/screens/watchlist_screen.dart:368`.
Son ikisinde `?? 'discover'` fallback'i kaldırılır; `recoSource` doğrudan geçilir
ve API `null`'ı yutar.

### Beklenen yan etki

v2 boşken tüm oranlar Laplace önceliğiyle 0.5 çıkar, oran oranları 1.0 olur:
`seedCount = 3`, `exploreRate = 0.12`. Motor veri birikene kadar nötr
varsayılanlarda çalışır. `base` sabitlerinin yeniden ayarlanması gerekmez, çünkü
knob'lar mutlak oranı değil **oranların oranını** kullanıyor — payda tanımı
değişse de bu oran ~1 civarında kalır.

---

## Faz 1B — `GET /admin/recommendations/calibration`

Mevcut admin ucunun yanına (`backend/api/index.php:490`), aynı `X-Admin-Key`
koruması ve `admin_key` boşken 404 davranışıyla. Parametreler: `days` (varsayılan
30, `report()` ile aynı 1–90 clamp'i), `bins` (`like_curve` kova sayısı,
varsayılan 20).

Rapor iki blok döndürür, çünkü iki farklı soruya cevap veriyorlar.

### `quantiles` — eşlemenin kaynağı

`model_version` başına, `score_components.final` dağılımının p0, p5, …, p100
değerleri (21 nokta). Kaynak: **tüm yüzeylerdeki** `action = 'shown'` olayları.

Rozet her yüzeyde göründüğü için referans dağılım da yüzey-bağımsız olmalı. "%85"
şu anlama gelir: *gösterilen adayların en iyi %15'lik dilimi*.

**Bellek:** 90 günlük olay taraması (`recommendation_event_retention_days`,
`backend/src/Config.php:16`) için tüm raw değerlerini belleğe almayız. Raw'lar
0.001 çözünürlüklü bir histogramda toplanır, kuantiller histogramdan okunur —
satır sayısından bağımsız sabit bellek.

### `like_curve` — doğrulama gate'i

`model_version` başına, raw skoru `bins` adet eşit kovaya bölüp her kovada
`{bin_lo, bin_hi, shown, rated, liked, like_rate}`.

Kaynak: **yalnız `surface = 'swipe'`**. Kodun kendi tespitiyle
(`lib/services/recommendation_telemetry_service.dart:32`) pozisyon yanlılığı
olmayan tek yüzey orası: kullanıcı her kartı görüp aksiyon almak zorunda.

`liked`, `rated` olayının `metadata.rating >= 2` koşulundan türetilir
(`lib/screens/swipe_screen.dart:97` metadata'yı zaten taşıyor).

Bu blok eşlemeyi kurmaz; **Faz 2'nin go/no-go koşuludur**: `like_rate` raw ile
birlikte artmıyorsa skor beğeniyi öngörmüyor demektir ve kalibrasyonun anlamı
kalmaz.

### Uygulama notları

Toplama PHP tarafında yapılır, mevcut `report()` üslubuyla — SQL'de JSON
ayrıştırma yok. Hem MySQL/SQLite farkından kaçınılır hem de dosyanın mevcut
deseni budur.

Aynı `impression_id`'ye birden fazla `rated` olayı düşerse (yeniden oylama) en
yenisi kazanır. `score_components` veya `metadata` bozuk/eksik JSON ise o olay
sessizce atlanır, rapor çökmez.

---

## Faz 2 — Persentil eşlemesi

**Ön koşul:** Faz 1B raporu çalıştırılmış, `like_curve` monoton çıkmış ve
`model_version` başına en az ~500 oylanmış swipe gösterimi birikmiş olmalı. İki
kol ayrı ayrı değerlendirilir; biri hazır diğeri değilse yalnız hazır olanı
gömülür.

### Eşlemenin temsili: kuantil tablosu

`RecommendationExperiment` her kol için kendi tablosunu taşır:

```dart
final List<double> rawQuantiles;   // p0, p5, ..., p100 — 21 eleman, azalmayan
```

`toDisplayScore` raw'ı bu tabloda parçalı doğrusal interpolasyonla persentile
çevirir:

```dart
static int toDisplayScore(
  double raw, {
  RecommendationExperiment experiment = RecommendationExperimentService.control,
});
// raw → kuantil interpolasyonu → persentil → clamp(5, 99)
```

`[5, 99]` clamp'i "%0 uyum" ve "%100 garanti" uçlarını kapatır. `rankForYou` zaten
`experiment`'i elinde tutuyor; üç çağrı noktası (`:895`, `:966`, `:976`) doğrudan
geçirir.

**Neden fit değil tablo?** İki parametreli lojistik fit daha az veri taşır ama fit
hatası ekler ve dağılım simetrik olmadığı için (kültür/bağlam boost'ları yüzünden
olmayacak) uçlarda sapar. Rapor kuantilleri zaten üretiyor; aradaki tek fark 21
sayı yerine 2 sayı taşımak — bunun karşılığında doğruluk vermeye değmez.

### Uç durumlar

- `raw < p0` → 5, `raw > p100` → 99
- Dejenere tablo (tüm değerler eşit) → sıfıra bölme guard'ı, sabit değer döner
- Tablosu olmayan/bilinmeyen kol → `control` tablosuna düşer

### Bayatlama kuralı

Kuantil tablosu ağırlıklara bağlıdır: `blend` ağırlıkları veya boost sabitleri
değişirse raw dağılımı kayar ve tablo yalan söyler. Bu yüzden tablo
`RecommendationExperiment`'in içinde yaşıyor ve şu kural geçerlidir:

> **Ağırlık veya boost sabitleri değişirse `modelVersion` de değişmeli, kuantil
> tablosu da yeniden ölçülmelidir.**

---

## Test stratejisi

**Dart**

- `test/prefs_service_test.dart` — mevcut telemetri testleri yeni API'ye taşınır:
  `shown`/`liked` ayrımı; v2 anahtarı; `null` kaynağın yok sayılması; revert'in
  `shown`'a dokunmaması; sayaçların negatife düşmemesi; eşzamanlı yazımların
  kuyruklanması.
- `test/recommendation_engine_test.dart` — `adaptiveExploreRate` ve adaptif tohum
  sayısı testleri yeni sayaç anlamıyla güncellenir. `toDisplayScore` testlerine
  Faz 1'de dokunulmaz.
- Faz 2'de yeni: kuantil interpolasyonu — tablo içi nokta, iki nokta arası,
  tablo altı/üstü raw, dejenere tablo, monotonluk özelliği, kol başına farklı
  tablo.

**PHP**

- `backend/tests/RecommendationAnalyticsTest.php` — kalibrasyon raporu SQLite
  üstünde: kova sayımları; aynı gösterime iki `rated` olayında en yenisinin
  kazanması; bozuk/eksik JSON'a dayanıklılık; `model_version` ayrımı;
  `like_curve`'ün yalnız swipe olaylarını sayması; `quantiles`'ın tüm yüzeyleri
  sayması; admin key koruması; boş veride çökmeme.

## Teslim sırası

Faz 1 tek parça, sırayla:

1. `PrefsRecoSignals` yeni API + v2 anahtarı
2. Çağrı yerlerinin güncellenmesi (3 yeni `shown`, 2 `liked`, 4 revert)
3. Dart testleri
4. Backend kalibrasyon raporu + rota
5. PHP testleri

Faz 2 ayrı iş; rapor çıktısı elde edildikten sonra planlanır.
