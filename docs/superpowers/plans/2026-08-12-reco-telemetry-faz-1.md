# Öneri Telemetrisi Faz 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cihaz-içi öneri sayacını "oylandı" yerine gerçek gösterim sayacak hale getirmek ve skor kalibrasyonu için gereken ölçüm ucunu backend'e eklemek.

**Architecture:** İki bağımsız parça. Dart tarafında `PrefsRecoSignals` sayaç API'si `shown`/`liked` olarak ikiye ayrılıyor, `reco_telemetry_v2` anahtarına taşınıyor ve atıfsız (`recoSource == null`) yapımları API'nin kendisi eliyor. PHP tarafında `RecommendationAnalytics`'e ikinci bir rapor ekleniyor: tüm yüzeylerin raw skor kuantilleri (persentil eşlemesinin kaynağı) ve yalnız swipe'ın raw→beğeni eğrisi (doğrulama gate'i).

**Tech Stack:** Flutter/Dart (shared_preferences, flutter_test), PHP 8 + PDO + PHPUnit 11, MySQL üretimde / SQLite testte.

**Spec:** `docs/superpowers/specs/2026-08-12-reco-telemetry-and-score-calibration-design.md`

## Global Constraints

- Faz 2 (kuantil tablosunun koda gömülmesi, `toDisplayScore` değişikliği) bu planın **dışında**. `toDisplayScore` bu planda değişmez.
- Cihaz-içi sayaç anahtarı `reco_telemetry_v2`; `reco_telemetry_v1` verisi taşınmaz, silinir.
- Atıfsız yapım (`recoSource == null`) hiçbir sayaca yazılmaz. Kural API'nin içinde yaşar, çağrı yerlerinde tekrar edilmez.
- Rapor toplaması PHP tarafında yapılır; SQL'de JSON ayrıştırma yok (MySQL/SQLite farkı ve dosyanın mevcut deseni).
- Rapor 1–90 gün clamp'ini `report()` ile aynı şekilde uygular: `max(1, min(90, $days))`.
- Git akışı: doğrudan `main`'e commit; her task kendi commit'i.
- Dart testleri: `flutter test <dosya>`. PHP testleri: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter <TestSınıfı>`.

---

### Task 1: Cihaz-içi telemetri semantiği

Sayaç API'si, depolama anahtarı ve dokuz çağrı yeri tek bir derleme birimidir — API'yi değiştirip çağrı yerlerini bırakmak kodu derlenmez hale getirir. Bu yüzden hepsi tek task.

**Files:**
- Modify: `lib/services/prefs/taste/reco_signals.dart:18-106`
- Modify: `lib/services/prefs/taste_prefs.dart:42-53`
- Modify: `lib/screens/browse_screen.dart:513-517`, `lib/screens/browse_screen.dart:636-638`
- Modify: `lib/screens/swipe_screen.dart:270-278`
- Modify: `lib/providers/swipe_provider.dart:354-360`, `lib/providers/swipe_provider.dart:396-402`
- Modify: `lib/screens/movie_detail_sheet.dart:476-481`, `lib/screens/movie_detail_sheet.dart:512-518`
- Modify: `lib/screens/profile_screen.dart:231-235`
- Modify: `lib/screens/watchlist_screen.dart:367-371`
- Test: `test/prefs_service_test.dart:95-168`
- Test: `test/recommendation_engine_test.dart:634` (yalnız anahtar adı)

**Interfaces:**
- Produces: `PrefsRecoSignals.recordRecoShown(Iterable<String?> sources)`, `PrefsRecoSignals.recordRecoLiked(String? source)`, `PrefsRecoSignals.revertRecoLiked(String? source)` — üçü de `Future<void>` döner. `PrefsTastePrefs` üzerinde aynı imzalarla forwarder'ları bulunur. `PrefsRecoSignals.getRecoTelemetry()` imzası değişmez (`Future<Map<String, Map<String, int>>>`) ama artık `reco_telemetry_v2`'yi okur.
- Consumes: yok (ilk task).

- [ ] **Step 1: Eski telemetri testlerini yeni API'nin testleriyle değiştir**

`test/prefs_service_test.dart` içinde 95-168 satırlarındaki iki testi (`revertRecoOutcome should correctly decrement...` ve `concurrent recommendation outcomes do not lose increments`) sil, yerlerine şunları koy:

```dart
    test('recordRecoShown kaynak başına sayar ve atıfsızları eler', () async {
      await PrefsTastePrefs.recordRecoShown([
        'discover',
        'seed',
        null,
        'discover',
      ]);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 2);
      expect(telemetry['discover']?['liked'], 0);
      expect(telemetry['seed']?['shown'], 1);
      expect(telemetry.keys, isNot(contains('null')));
    });

    test('recordRecoLiked yalnız liked sayacını artırır', () async {
      await PrefsTastePrefs.recordRecoShown(['discover', 'discover', 'discover']);
      await PrefsTastePrefs.recordRecoLiked('discover');
      await PrefsTastePrefs.recordRecoLiked('discover');
      await PrefsTastePrefs.recordRecoLiked(null);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 3);
      expect(telemetry['discover']?['liked'], 2);
    });

    test('revertRecoLiked gösterim sayacına dokunmaz', () async {
      await PrefsTastePrefs.recordRecoShown(['discover', 'discover']);
      await PrefsTastePrefs.recordRecoLiked('discover');

      await PrefsTastePrefs.revertRecoLiked('discover');

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 2);
      expect(telemetry['discover']?['liked'], 0);
    });

    test('revertRecoLiked negatife düşmez ve atıfsızı yok sayar', () async {
      await PrefsTastePrefs.revertRecoLiked('discover');
      await PrefsTastePrefs.revertRecoLiked(null);

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['liked'], 0);
      expect(telemetry.keys, isNot(contains('null')));
    });

    test('eşzamanlı gösterim yazımları artışları kaybetmez', () async {
      await Future.wait(
        List.generate(
          50,
          (_) => PrefsTastePrefs.recordRecoShown(['discover']),
        ),
      );

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();
      expect(telemetry['discover']?['shown'], 50);
    });

    test('v1 telemetri anahtarı okunmaz ve silinir', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'reco_telemetry_v1',
        jsonEncode({
          'discover': {'shown': 99, 'liked': 99},
        }),
      );

      final telemetry = await PrefsTastePrefs.getRecoTelemetry();

      expect(telemetry['discover'], isNull);
      expect(prefs.getString('reco_telemetry_v1'), isNull);
    });

    test('bozuk telemetri yükü boş okunur', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('reco_telemetry_v2', 'json değil');

      expect(await PrefsTastePrefs.getRecoTelemetry(), isEmpty);
    });
```

Dosyanın başına `import 'dart:convert';` ekle (`jsonEncode` için; mevcut import listesinde yok).

- [ ] **Step 2: Testleri çalıştır, derlenmediğini doğrula**

Run: `flutter test test/prefs_service_test.dart`
Expected: FAIL — `The method 'recordRecoShown' isn't defined for the type 'PrefsTastePrefs'`

- [ ] **Step 3: `PrefsRecoSignals` sayaç bölümünü yeniden yaz**

`lib/services/prefs/taste/reco_signals.dart` içinde 18-106 satırlarındaki bloğu (anahtar sabiti, `_enqueueRecoTelemetry`, `_asInt`, `recordRecoOutcome`, `revertRecoOutcome`, `getRecoTelemetry`) şununla değiştir:

```dart
  static const _keyRecoTelemetry = 'reco_telemetry_v2';
  static const _keyLegacyRecoTelemetry = 'reco_telemetry_v1';
  static Future<void> _recoTelemetryTail = Future<void>.value();
  static bool _legacyPurged = false;

  static Future<void> _enqueueRecoTelemetry(Future<void> Function() operation) {
    final previous = _recoTelemetryTail;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later telemetry updates.
      }
      await operation();
    }();
    _recoTelemetryTail = current;
    return current;
  }

  static int _asInt(Object? v) =>
      v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  /// Bozuk yük yeni sayaç gibi davranır — telemetri hiçbir zaman akışı kırmaz.
  static Map<String, dynamic> _decodeTelemetry(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  static Map<String, dynamic> _bucketOf(
    Map<String, dynamic> data,
    String source,
  ) {
    final value = data[source];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : {'shown': 0, 'liked': 0};
  }

  /// Gösterim: kaynak başına `shown++`. Atıfsız (`null`) yapımlar elenir —
  /// arama gibi öneri motoru dışı yüzeyler sayaçları kirletmesin.
  static Future<void> recordRecoShown(Iterable<String?> sources) {
    final counted = sources.whereType<String>().toList(growable: false);
    if (counted.isEmpty) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      for (final source in counted) {
        final bucket = _bucketOf(data, source);
        bucket['shown'] = _asInt(bucket['shown']) + 1;
        data[source] = bucket;
      }
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// İsabet: yalnızca İyi/Harika (rating >= 2) oy geldiğinde çağrılır.
  static Future<void> recordRecoLiked(String? source) {
    if (source == null) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      final bucket = _bucketOf(data, source);
      bucket['liked'] = _asInt(bucket['liked']) + 1;
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// Puan silindi: isabeti geri al. `shown`'a DOKUNMAZ — gösterim gerçekten
  /// olmuştu, kullanıcının fikrini değiştirmesi onu geri almaz.
  static Future<void> revertRecoLiked(String? source) {
    if (source == null) return Future<void>.value();
    return _enqueueRecoTelemetry(() async {
      final prefs = await SharedPreferences.getInstance();
      final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
      final bucket = _bucketOf(data, source);
      final liked = _asInt(bucket['liked']);
      if (liked > 0) bucket['liked'] = liked - 1;
      data[source] = bucket;
      await prefs.setString(_keyRecoTelemetry, jsonEncode(data));
    });
  }

  /// Kaynak → {shown, liked} sayaçları. Beğeni oranı = liked/shown.
  static Future<Map<String, Map<String, int>>> getRecoTelemetry() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_legacyPurged) {
      _legacyPurged = true;
      // v1'in paydası "oylandı"ydı; v2'ninki "gösterildi". Karışım her iki
      // oranı da bozar, o yüzden taşınmaz — silinir.
      await prefs.remove(_keyLegacyRecoTelemetry);
    }
    final data = _decodeTelemetry(prefs.getString(_keyRecoTelemetry));
    return data.map(
      (k, v) => MapEntry(
        k,
        v is Map
            ? Map<String, dynamic>.from(
                v,
              ).map((k2, v2) => MapEntry(k2, _asInt(v2)))
            : <String, int>{},
      ),
    );
  }
```

Aynı dosyanın en altındaki `resetInMemoryCaches` metodunu güncelle ki testler arasında purge bayrağı sıfırlansın:

```dart
  static void resetInMemoryCaches() {
    _recoTelemetryTail = Future<void>.value();
    _legacyPurged = false;
  }
```

Sınıfın üstündeki doc yorumundaki "kaç öneri gösterilip kaçının İyi/Harika aldığını sayar" cümlesi artık doğru — dokunma.

- [ ] **Step 4: Cepheyi (`PrefsTastePrefs`) güncelle**

`lib/services/prefs/taste_prefs.dart` içinde 42-50 satırlarındaki `recordRecoOutcome` ve `revertRecoOutcome` forwarder'larını sil, yerlerine:

```dart
  static Future<void> recordRecoShown(Iterable<String?> sources) =>
      PrefsRecoSignals.recordRecoShown(sources);

  static Future<void> recordRecoLiked(String? source) =>
      PrefsRecoSignals.recordRecoLiked(source);

  static Future<void> revertRecoLiked(String? source) =>
      PrefsRecoSignals.revertRecoLiked(source);
```

- [ ] **Step 5: Prefs testlerini çalıştır**

Run: `flutter test test/prefs_service_test.dart`
Expected: PASS (yeni yedi test dahil)

Test asılı kalırsa: takılı `hook.dill` sürecini öldür (sqlite3 hooks_runner kilidi), sonra tekrar dene.

- [ ] **Step 6: Gösterim (`shown`) çağrı yerlerini ekle — Keşfet**

`lib/screens/browse_screen.dart:513-517`. Mevcut:

```dart
      final shownKeys = <String>[
        if (tonightPick != null) _movieKey(tonightPick),
        ...finalPersonal.take(10).map(_movieKey),
      ];
      unawaited(PrefsTastePrefs.recordRecoImpressions(shownKeys));
```

Yerine:

```dart
      final shownMovies = <Movie>[
        if (tonightPick != null) tonightPick,
        ...finalPersonal.take(10),
      ];
      unawaited(
        PrefsTastePrefs.recordRecoImpressions(
          shownMovies.map(_movieKey).toList(),
        ),
      );
      // İsabet telemetrisinin paydası: gösterim hafızasıyla AYNI küme.
      unawaited(
        PrefsTastePrefs.recordRecoShown(shownMovies.map((m) => m.recoSource)),
      );
```

`lib/screens/browse_screen.dart:638`. Mevcut satırın hemen altına ekle:

```dart
      unawaited(PrefsTastePrefs.recordRecoImpressions([_movieKey(pick)]));
      unawaited(PrefsTastePrefs.recordRecoShown([pick.recoSource]));
```

Import gerekmez: `dart:async`, `Movie` ve `PrefsTastePrefs` zaten dosyada.

- [ ] **Step 7: Gösterim (`shown`) çağrı yerini ekle — Swipe**

`lib/screens/swipe_screen.dart:270-278` içindeki `addPostFrameCallback` gövdesi. Mevcut `RecommendationTelemetryService.recordShown(...)` çağrısının hemen ardına ekle:

```dart
          RecommendationTelemetryService.recordShown(
            [movie],
            surface: 'swipe',
            slot: 'card',
          );
          PrefsTastePrefs.recordRecoShown([movie.recoSource]);
```

Dosyanın import listesine ekle (yok):

```dart
import '../services/prefs/taste_prefs.dart';
```

Çevredeki kodla tutarlı olsun diye `unawaited` sarmalaması kullanma — mevcut `recordShown` çağrısı da çıplak.

- [ ] **Step 8: İsabet (`liked`) ve geri alma çağrı yerlerini güncelle**

`lib/providers/swipe_provider.dart:354-360`. Mevcut:

```dart
    // İsabet telemetrisi: hangi aday kaynağı gerçekten beğeni üretiyor?
    // (rating>=2 = İyi/Harika → isabet). Best-effort; akışı bloklamaz.
    PrefsTastePrefs.recordRecoOutcome(
      source: movie.recoSource ?? 'discover',
      liked: rating >= 2,
    ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));
```

Yerine:

```dart
    // İsabet telemetrisi: hangi aday kaynağı gerçekten beğeni üretiyor?
    // (rating>=2 = İyi/Harika → isabet). Best-effort; akışı bloklamaz.
    // Payda gösterim anında yazıldı; burada yalnız isabet sayılır.
    if (rating >= 2) {
      PrefsTastePrefs.recordRecoLiked(
        movie.recoSource,
      ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));
    }
```

`lib/providers/swipe_provider.dart:396-402`. Mevcut:

```dart
    if (prevRating != null) {
      PrefsTastePrefs.revertRecoOutcome(
        source: movie.recoSource ?? 'discover',
        liked: prevRating >= 2,
      ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
    }
```

Yerine:

```dart
    if (prevRating != null && prevRating >= 2) {
      PrefsTastePrefs.revertRecoLiked(
        movie.recoSource,
      ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
    }
```

`lib/screens/movie_detail_sheet.dart:512-518`. Mevcut `if (recoSource != null) { ... recordRecoOutcome ... }` bloğunu şununla değiştir (dış `null` kontrolü artık API'de, kaldırılıyor):

```dart
        // İsabet telemetrisi: atıfsız yapımlar API içinde elenir.
        if (rating >= 2) {
          PrefsTastePrefs.recordRecoLiked(
            widget.movie.recoSource,
          ).catchError((e) => debugPrint("Reco telemetry write failed: $e"));
        }
```

`lib/screens/movie_detail_sheet.dart:476-481`. Mevcut:

```dart
        final recoSource = widget.movie.recoSource;
        if (recoSource != null && oldRating != null) {
          PrefsTastePrefs.revertRecoOutcome(
            source: recoSource,
            liked: oldRating >= 2,
          ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
        }
```

Yerine:

```dart
        if (oldRating != null && oldRating >= 2) {
          PrefsTastePrefs.revertRecoLiked(
            widget.movie.recoSource,
          ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
        }
```

`lib/screens/profile_screen.dart:231-235`. Mevcut:

```dart
      if (prevRating != null) {
        PrefsTastePrefs.revertRecoOutcome(
          source: movie.recoSource ?? 'discover',
          liked: prevRating >= 2,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
```

Yerine — **`?? 'discover'` fallback'i kaldırılıyor**; kütüphaneden gelen filmde `recoSource` her zaman `null` olduğu için bu fallback `discover` sayacını haksız yere düşürüyordu:

```dart
      if (prevRating != null && prevRating >= 2) {
        PrefsTastePrefs.revertRecoLiked(
          movie.recoSource,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
```

`lib/screens/watchlist_screen.dart:367-371`. Aynı düzeltme, birebir aynı yeni gövde:

```dart
      if (prevRating != null && prevRating >= 2) {
        PrefsTastePrefs.revertRecoLiked(
          movie.recoSource,
        ).catchError((e) => debugPrint("Reco telemetry revert failed: $e"));
      }
```

- [ ] **Step 9: Motor testindeki anahtar adını güncelle**

`test/recommendation_engine_test.dart:634` içindeki `'reco_telemetry_v1'` dizesini `'reco_telemetry_v2'` yap. Testin geri kalanına dokunma — `{'seed': {shown:10, liked:8}, 'discover': {shown:10, liked:2}}` kurgusu yeni semantikte de geçerli (oran 4.0 → `3 * 4.0 = 12`, clamp ile 6 tohum).

- [ ] **Step 10: Tüm test paketini çalıştır**

Run: `flutter test`
Expected: PASS. Başarısız olan varsa `recordRecoOutcome`/`revertRecoOutcome` kalıntısı aranmalı:

Run: `flutter analyze`
Expected: eski API'ye referans kalmamalı.

- [ ] **Step 11: Commit**

```bash
git add lib/services/prefs/taste/reco_signals.dart lib/services/prefs/taste_prefs.dart lib/screens/browse_screen.dart lib/screens/swipe_screen.dart lib/providers/swipe_provider.dart lib/screens/movie_detail_sheet.dart lib/screens/profile_screen.dart lib/screens/watchlist_screen.dart test/prefs_service_test.dart test/recommendation_engine_test.dart
git commit -m "fix(reco): isabet telemetrisi gösterimi sayar, oylamayı değil"
```

---

### Task 2: `adaptiveExploreRate` regresyon testi

Keşif oranı hiç test edilmiyor; yeni sayaç semantiğiyle davranışının sabitlendiğini göstermek gerek.

**Files:**
- Test: `test/recommendation_engine_test.dart` (`RecommendationEngine Adaptive Telemetry Integration Tests` grubunun sonuna)

**Interfaces:**
- Consumes: Task 1'in `reco_telemetry_v2` anahtarı ve `{shown, liked}` kova şeması.
- Produces: yok.

- [ ] **Step 1: Testleri yaz**

`test/recommendation_engine_test.dart` içinde `RecommendationEngine Adaptive Telemetry Integration Tests` grubunun kapanış parantezinden önce ekle:

```dart
    test(
      'adaptiveExploreRate, keşif dönüşümü iyiyken üst sınıra dayanır',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'reco_telemetry_v2',
          jsonEncode({
            'explore': {'shown': 100, 'liked': 60},
            'discover': {'shown': 100, 'liked': 10},
          }),
        );

        final engine = RecommendationEngine(TmdbService(client: MockClient((_) async => http.Response('{}', 200))));

        expect(await engine.adaptiveExploreRate(), 0.20);
      },
    );

    test(
      'adaptiveExploreRate, keşif dönüşümü kötüyken alt sınırda kalır',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'reco_telemetry_v2',
          jsonEncode({
            'explore': {'shown': 100, 'liked': 1},
            'discover': {'shown': 100, 'liked': 60},
          }),
        );

        final engine = RecommendationEngine(TmdbService(client: MockClient((_) async => http.Response('{}', 200))));

        expect(await engine.adaptiveExploreRate(), 0.05);
      },
    );

    test('adaptiveExploreRate, veri yokken tabana düşer', () async {
      final engine = RecommendationEngine(TmdbService(client: MockClient((_) async => http.Response('{}', 200))));

      expect(await engine.adaptiveExploreRate(), closeTo(0.12, 1e-9));
    });
```

- [ ] **Step 2: Testleri çalıştır**

Run: `flutter test test/recommendation_engine_test.dart --plain-name "adaptiveExploreRate"`
Expected: PASS — üçü de. Fail ederse beklenen değeri değil kodu incele; `adaptiveExploreRate` mevcut haliyle bu değerleri üretmeli (`0.12 * (0.598/0.108) = 0.66 → clamp 0.20`; `0.12 * (0.0196/0.598) = 0.0039 → clamp 0.05`; boş veride `0.12 * 1.0`).

- [ ] **Step 3: Commit**

```bash
git add test/recommendation_engine_test.dart
git commit -m "test(reco): adaptiveExploreRate sınırlarını sabitle"
```

---

### Task 3: Kalibrasyon raporu — raw skor kuantilleri

Persentil eşlemesinin kaynağı. Tüm yüzeylerdeki `shown` olaylarının raw skor dağılımı, sabit bellekli histogramdan okunur.

**Files:**
- Modify: `backend/src/RecommendationAnalytics.php` (yeni public metot + private yardımcılar)
- Test: `backend/tests/RecommendationAnalyticsTest.php`

**Interfaces:**
- Consumes: yok.
- Produces: `RecommendationAnalytics::calibration(int $days, int $bins = 20, ?int $nowMs = null): array` — Task 4 aynı metodu `like_curve` bloğuyla genişletir, Task 5 rota bağlar. Bu task'te dönen dizi `period_days`, `bins`, `since`, `generated_at`, `quantiles` anahtarlarını içerir; `quantiles` her eleman `{model_version, shown, percentiles}` şeklindedir ve `percentiles` `p0`…`p100` (5'er adım, 21 anahtar) taşır.

- [ ] **Step 1: Failing test yaz**

`backend/tests/RecommendationAnalyticsTest.php`. Önce `setUp` içindeki tablo şemasını genişlet — kalibrasyon `score_components` ve `metadata` sütunlarına ihtiyaç duyuyor:

```php
        $this->db->exec(
            'CREATE TABLE recommendation_events (
                event_id TEXT PRIMARY KEY,
                impression_id TEXT NOT NULL,
                action TEXT NOT NULL,
                surface TEXT NOT NULL,
                model_version TEXT NOT NULL,
                score_components TEXT NULL,
                metadata TEXT NULL,
                created_at INTEGER NOT NULL
            )'
        );
```

Mevcut `event()` yardımcısı bu iki sütunu yazmadığından olduğu gibi çalışmaya devam eder (NULL kalırlar). Yanına ikinci bir yardımcı ekle:

```php
    private function scoredEvent(
        string $eventId,
        string $impressionId,
        string $action,
        string $surface,
        string $model,
        int $createdAt,
        ?float $raw = null,
        ?int $rating = null,
    ): void {
        $stmt = $this->db->prepare(
            'INSERT INTO recommendation_events
             (event_id, impression_id, action, surface, model_version,
              score_components, metadata, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $eventId,
            $impressionId,
            $action,
            $surface,
            $model,
            $raw === null ? null : json_encode(['final' => $raw]),
            $rating === null ? null : json_encode(['rating' => $rating]),
            $createdAt,
        ]);
    }
```

Sonra testi ekle:

```php
    public function testCalibrationReportsRawQuantilesAcrossSurfaces(): void
    {
        // v1: 0.0, 0.1, ..., 0.9 — iki farklı yüzeye dağılmış.
        for ($i = 0; $i < 10; $i++) {
            $this->scoredEvent(
                'q' . $i,
                'i' . $i,
                'shown',
                $i % 2 === 0 ? 'browse' : 'swipe',
                'v1',
                99_000_000 + $i,
                $i / 10,
            );
        }
        // Başka kol, tek nokta.
        $this->scoredEvent('q10', 'i10', 'shown', 'browse', 'v2', 99_000_010, 0.5);
        // Gösterim olmayan olay, NULL yük ve bozuk yük sayılmamalı.
        $this->scoredEvent('q11', 'i0', 'rated', 'browse', 'v1', 99_000_011, 5.0);
        $this->event('q12', 'i12', 'shown', 'browse', 'v1', 99_000_012);
        $this->db->exec(
            "INSERT INTO recommendation_events
             (event_id, impression_id, action, surface, model_version,
              score_components, metadata, created_at)
             VALUES ('q13', 'i13', 'shown', 'browse', 'v1', 'json değil', NULL, 99000013),
                    ('q14', 'i14', 'shown', 'browse', 'v1', '{\"genre\":0.4}', NULL, 99000014)"
        );

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 20, 100_000_000);

        self::assertCount(2, $report['quantiles']);

        $v1 = $report['quantiles'][0];
        self::assertSame('v1', $v1['model_version']);
        self::assertSame(10, $v1['shown']);
        self::assertEqualsWithDelta(0.0, $v1['percentiles']['p0'], 0.001);
        self::assertEqualsWithDelta(0.9, $v1['percentiles']['p100'], 0.001);
        self::assertEqualsWithDelta(0.5, $v1['percentiles']['p50'], 0.051);
        self::assertCount(21, $v1['percentiles']);

        $v2 = $report['quantiles'][1];
        self::assertSame(1, $v2['shown']);
        self::assertEqualsWithDelta(0.5, $v2['percentiles']['p0'], 0.001);
        self::assertEqualsWithDelta(0.5, $v2['percentiles']['p100'], 0.001);
    }

    public function testCalibrationClampsPeriodAndBins(): void
    {
        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(365, 1000, 1000);

        self::assertSame(90, $report['period_days']);
        self::assertSame(100, $report['bins']);
        self::assertSame([], $report['quantiles']);
    }
```

- [ ] **Step 2: Testleri çalıştır, düştüğünü doğrula**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter RecommendationAnalyticsTest`
Expected: FAIL — `Call to undefined method RecommendationAnalytics::calibration()`

- [ ] **Step 3: `calibration()` metodunu kuantil bloğuyla yaz**

`backend/src/RecommendationAnalytics.php` içinde `report()` metodunun ardına ekle:

```php
    /**
     * Skor kalibrasyonu ölçümü.
     *
     * `quantiles`: TÜM yüzeylerdeki gösterimlerin ham skor dağılımı — rozet her
     * yüzeyde göründüğü için persentil eşlemesinin referansı da yüzey-bağımsız
     * olmalı.
     *
     * @return array<string, mixed>
     */
    public function calibration(int $days, int $bins = 20, ?int $nowMs = null): array
    {
        $days = max(1, min(90, $days));
        $bins = max(4, min(100, $bins));
        $nowMs ??= now_ms();
        $since = $nowMs - ($days * 86_400_000);

        $stmt = $this->db->prepare(
            "SELECT model_version, score_components
             FROM recommendation_events
             WHERE action = 'shown' AND created_at >= ?"
        );
        $stmt->execute([$since]);

        // Sabit bellek: ham değerleri saklamayız, 0.001 çözünürlüklü histogram
        // tutarız. 90 günlük tarama satır sayısından bağımsız çalışır.
        $histograms = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $raw = $this->rawScore($row['score_components']);
            if ($raw === null) continue;
            $model = (string) $row['model_version'];
            $slot = (int) round($raw * 1000);
            $histograms[$model][$slot] = ($histograms[$model][$slot] ?? 0) + 1;
        }

        ksort($histograms);
        $quantiles = [];
        foreach ($histograms as $model => $histogram) {
            $quantiles[] = [
                'model_version' => $model,
                'shown' => array_sum($histogram),
                'percentiles' => $this->percentiles($histogram),
            ];
        }

        return [
            'period_days' => $days,
            'bins' => $bins,
            'since' => $since,
            'generated_at' => $nowMs,
            'quantiles' => $quantiles,
        ];
    }

    /** Bozuk/eksik yük sessizce atlanır — rapor tek bir kayıt yüzünden çökmez. */
    private function rawScore(mixed $scoreComponents): ?float
    {
        if (!is_string($scoreComponents) || $scoreComponents === '') return null;
        $decoded = json_decode($scoreComponents, true);
        if (!is_array($decoded) || !isset($decoded['final'])) return null;
        return is_numeric($decoded['final']) ? (float) $decoded['final'] : null;
    }

    /**
     * p0, p5, ..., p100 — histogramdan en yakın-sıra yöntemiyle.
     *
     * @param array<int, int> $histogram slot (raw*1000) => adet
     * @return array<string, float>
     */
    private function percentiles(array $histogram): array
    {
        ksort($histogram);
        $total = array_sum($histogram);
        $slots = array_keys($histogram);

        $targets = [];
        for ($p = 0; $p <= 100; $p += 5) {
            $targets[$p] = (int) ceil($p / 100 * ($total - 1));
        }

        $result = [];
        $index = 0;
        $seen = 0;
        foreach ($targets as $p => $target) {
            while ($seen + $histogram[$slots[$index]] <= $target
                   && $index < count($slots) - 1) {
                $seen += $histogram[$slots[$index]];
                $index++;
            }
            $result['p' . $p] = $slots[$index] / 1000;
        }

        return $result;
    }
```

- [ ] **Step 4: Testleri çalıştır**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter RecommendationAnalyticsTest`
Expected: PASS (mevcut `report()` testleri dahil hepsi)

- [ ] **Step 5: Commit**

```bash
git add backend/src/RecommendationAnalytics.php backend/tests/RecommendationAnalyticsTest.php
git commit -m "feat(reco): kalibrasyon raporuna ham skor kuantilleri"
```

---

### Task 4: Kalibrasyon raporu — raw→beğeni eğrisi

Faz 2'nin go/no-go gate'i. Yalnız swipe yüzeyi sayılır: kullanıcı her kartı görüp aksiyon almak zorunda olduğu için pozisyon yanlılığı yok.

**Files:**
- Modify: `backend/src/RecommendationAnalytics.php` (`calibration()` genişletilir + private yardımcı)
- Test: `backend/tests/RecommendationAnalyticsTest.php`

**Interfaces:**
- Consumes: Task 3'ün `calibration(int $days, int $bins = 20, ?int $nowMs = null): array` metodu, `rawScore()` yardımcısı.
- Produces: dönen dizide `like_curve` anahtarı; her eleman `{model_version, bin, bin_lo, bin_hi, shown, rated, liked, like_rate}`.

- [ ] **Step 1: Failing test yaz**

`backend/tests/RecommendationAnalyticsTest.php` içine ekle:

```php
    public function testLikeCurveCountsOnlySwipeAndUsesLatestRating(): void
    {
        // Swipe: raw 0.0 (beğenilmedi) ve raw 1.0 (beğenildi).
        $this->scoredEvent('s1', 'a', 'shown', 'swipe', 'v1', 99_000_000, 0.0);
        $this->scoredEvent('s2', 'a', 'rated', 'swipe', 'v1', 99_000_001, null, 1);
        $this->scoredEvent('s3', 'b', 'shown', 'swipe', 'v1', 99_000_002, 1.0);
        $this->scoredEvent('s4', 'b', 'rated', 'swipe', 'v1', 99_000_003, 3);

        // Aynı gösterime ikinci oy: en yenisi kazanır (3 → 0, yani beğeni geri alındı).
        $this->scoredEvent('s5', 'b', 'rated', 'swipe', 'v1', 99_000_009, 0);

        // Oylanmamış swipe gösterimi: shown sayılır, rated sayılmaz.
        $this->scoredEvent('s6', 'c', 'shown', 'swipe', 'v1', 99_000_004, 1.0);

        // Browse yüzeyi eğriye HİÇ girmez (ama kuantillere girer).
        $this->scoredEvent('s7', 'd', 'shown', 'browse', 'v1', 99_000_005, 1.0);
        $this->scoredEvent('s8', 'd', 'rated', 'browse', 'v1', 99_000_006, 3);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 4, 100_000_000);

        // Kuantiller browse'u da saydı: 4 gösterim.
        self::assertSame(4, $report['quantiles'][0]['shown']);

        $curve = $report['like_curve'];
        self::assertCount(4, $curve);
        self::assertSame('v1', $curve[0]['model_version']);

        // İlk kova [0.0, 0.25): tek gösterim, oylandı, beğenilmedi.
        self::assertSame(0, $curve[0]['bin']);
        self::assertEqualsWithDelta(0.0, $curve[0]['bin_lo'], 0.001);
        self::assertSame(1, $curve[0]['shown']);
        self::assertSame(1, $curve[0]['rated']);
        self::assertSame(0, $curve[0]['liked']);
        self::assertSame(0.0, $curve[0]['like_rate']);

        // Son kova [0.75, 1.0]: iki gösterim, biri oylandı (en yeni oy 0 → beğeni yok).
        self::assertSame(2, $curve[3]['shown']);
        self::assertSame(1, $curve[3]['rated']);
        self::assertSame(0, $curve[3]['liked']);
    }

    public function testLikeCurveIsEmptyWithoutSwipeData(): void
    {
        $this->scoredEvent('b1', 'a', 'shown', 'browse', 'v1', 99_000_000, 0.5);

        $report = (new RecommendationAnalytics($this->db, 'secret'))
            ->calibration(1, 20, 100_000_000);

        self::assertSame([], $report['like_curve']);
        self::assertCount(1, $report['quantiles']);
    }
```

- [ ] **Step 2: Testleri çalıştır, düştüğünü doğrula**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter RecommendationAnalyticsTest`
Expected: FAIL — `Undefined array key "like_curve"`

- [ ] **Step 3: `calibration()` içine eğri hesabını ekle**

`calibration()` metodunda ilk sorgunun `while` döngüsünü, swipe gösterimlerinin ham skorunu da tutacak şekilde genişlet. Sorguyu ve döngüyü şununla değiştir:

```php
        $stmt = $this->db->prepare(
            "SELECT model_version, surface, impression_id, score_components
             FROM recommendation_events
             WHERE action = 'shown' AND created_at >= ?"
        );
        $stmt->execute([$since]);

        // Sabit bellek: ham değerleri saklamayız, 0.001 çözünürlüklü histogram
        // tutarız. 90 günlük tarama satır sayısından bağımsız çalışır.
        $histograms = [];
        // Eğri için yalnız swipe gösterimleri tutulur — payda orada yanlılıksız.
        $swipeRaw = [];
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $raw = $this->rawScore($row['score_components']);
            if ($raw === null) continue;
            $model = (string) $row['model_version'];
            $slot = (int) round($raw * 1000);
            $histograms[$model][$slot] = ($histograms[$model][$slot] ?? 0) + 1;
            if ((string) $row['surface'] === 'swipe') {
                $swipeRaw[(string) $row['impression_id']] = [$model, $raw];
            }
        }
```

Sonra `return` ifadesinden önce ekle:

```php
        $ratedStmt = $this->db->prepare(
            "SELECT impression_id, metadata
             FROM recommendation_events
             WHERE action = 'rated' AND created_at >= ?
             ORDER BY created_at ASC"
        );
        $ratedStmt->execute([$since]);

        // ASC sıra: aynı gösterime gelen ikinci oy birincinin üzerine yazar.
        $likedOf = [];
        while ($row = $ratedStmt->fetch(PDO::FETCH_ASSOC)) {
            $impression = (string) $row['impression_id'];
            if (!isset($swipeRaw[$impression])) continue;
            $rating = $this->ratingOf($row['metadata']);
            if ($rating === null) continue;
            $likedOf[$impression] = $rating >= 2;
        }
```

Ve `like_curve` toplamasını:

```php
        $byModel = [];
        foreach ($swipeRaw as $impression => [$model, $raw]) {
            $byModel[$model][] = [$raw, $likedOf[$impression] ?? null];
        }
        ksort($byModel);

        $likeCurve = [];
        foreach ($byModel as $model => $rows) {
            $values = array_column($rows, 0);
            $lo = min($values);
            $hi = max($values);
            $width = $hi > $lo ? ($hi - $lo) / $bins : 0.0;

            $buckets = array_fill(0, $bins, ['shown' => 0, 'rated' => 0, 'liked' => 0]);
            foreach ($rows as [$raw, $liked]) {
                $index = $width > 0.0
                    ? min($bins - 1, (int) floor(($raw - $lo) / $width))
                    : 0;
                $buckets[$index]['shown']++;
                if ($liked !== null) {
                    $buckets[$index]['rated']++;
                    if ($liked) $buckets[$index]['liked']++;
                }
            }

            foreach ($buckets as $index => $bucket) {
                $likeCurve[] = [
                    'model_version' => $model,
                    'bin' => $index,
                    'bin_lo' => round($lo + ($index * $width), 4),
                    'bin_hi' => round($lo + (($index + 1) * $width), 4),
                    'shown' => $bucket['shown'],
                    'rated' => $bucket['rated'],
                    'liked' => $bucket['liked'],
                    'like_rate' => $this->rate($bucket['liked'], $bucket['rated']),
                ];
            }
        }
```

`return` dizisine `'like_curve' => $likeCurve,` anahtarını ekle (`quantiles`'ın ardına).

`rawScore()`'un yanına ikinci yardımcı:

```php
    /** Bozuk/eksik metadata sessizce atlanır. */
    private function ratingOf(mixed $metadata): ?int
    {
        if (!is_string($metadata) || $metadata === '') return null;
        $decoded = json_decode($metadata, true);
        if (!is_array($decoded) || !isset($decoded['rating'])) return null;
        return is_numeric($decoded['rating']) ? (int) $decoded['rating'] : null;
    }
```

Not: `rate()` metodu paydası 0 olduğunda 0.0 döner (`backend/src/RecommendationAnalytics.php:92`), yani hiç oylanmamış kova `like_rate: 0.0` gösterir — `rated: 0` ile birlikte okunmalı.

- [ ] **Step 4: Testleri çalıştır**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter RecommendationAnalyticsTest`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/RecommendationAnalytics.php backend/tests/RecommendationAnalyticsTest.php
git commit -m "feat(reco): kalibrasyon raporuna swipe raw-beğeni eğrisi"
```

---

### Task 5: Rota ve admin koruması

**Files:**
- Modify: `backend/src/RecommendationAnalytics.php` (render metodu)
- Modify: `backend/api/index.php:490-495`
- Test: `backend/tests/RecommendationAnalyticsTest.php`

**Interfaces:**
- Consumes: Task 3+4'ün `calibration(int $days, int $bins = 20, ?int $nowMs = null): array` metodu.
- Produces: `GET /admin/recommendations/calibration?days=<n>&bins=<n>` — `X-Admin-Key` korumalı JSON uç.

- [ ] **Step 1: Failing test yaz**

```php
    public function testCalibrationEndpointRejectsMissingAdminKey(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);

        (new RecommendationAnalytics($this->db, 'secret'))->renderCalibration(30, 20);
    }

    public function testCalibrationEndpointHiddenWhenAdminKeyUnset(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(404);

        (new RecommendationAnalytics($this->db, ''))->renderCalibration(30, 20);
    }
```

- [ ] **Step 2: Testleri çalıştır, düştüğünü doğrula**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage --filter RecommendationAnalyticsTest`
Expected: FAIL — `Call to undefined method RecommendationAnalytics::renderCalibration()`

- [ ] **Step 3: Render metodunu ekle**

`backend/src/RecommendationAnalytics.php` içinde `renderReport()`'un hemen altına:

```php
    public function renderCalibration(int $days, int $bins): void
    {
        $this->requireAdmin();
        json_out(200, $this->calibration($days, $bins));
    }
```

- [ ] **Step 4: Rotayı bağla**

`backend/api/index.php` içinde `GET /admin/recommendations` case'inin hemen ardına ekle:

```php
    case $route === 'GET /admin/recommendations/calibration':
        rate_limit('admin_recommendations', 30, true);
        $recommendationAnalytics->renderCalibration(
            isset($_GET['days']) ? (int) $_GET['days'] : 30,
            isset($_GET['bins']) ? (int) $_GET['bins'] : 20,
        );
        break;
```

- [ ] **Step 5: Testleri çalıştır**

Run: `cd backend && php vendor/bin/phpunit --configuration phpunit.xml --no-coverage`
Expected: PASS — tüm backend paketi.

- [ ] **Step 6: Commit**

```bash
git add backend/src/RecommendationAnalytics.php backend/api/index.php backend/tests/RecommendationAnalyticsTest.php
git commit -m "feat(reco): kalibrasyon raporu için admin ucu"
```

---

## Faz 1 sonrası

Uç canlıya alındıktan sonra raporu çalıştır:

```bash
curl -4 -s -H "X-Admin-Key: <anahtar>" "https://<host>/admin/recommendations/calibration?days=30&bins=20"
```

Çıktıdaki `like_curve` monoton artıyorsa ve `model_version` başına en az ~500 `rated` birikmişse Faz 2 planlanabilir: `quantiles.percentiles` tablosu `RecommendationExperiment`'e gömülür ve `toDisplayScore` persentil eşlemesine geçer.
