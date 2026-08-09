# PrefsService Domain Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lib/services/prefs_service.dart` (~985 satır, 124 statik üye, graphify degree 138 / cohesion 0.016) içindeki karışık sorumlulukları domain sınıflarına ayır; mevcut `PrefsService.*` public API’sini değiştirmeden ince bir facade bırak.

**Architecture:** Dart’ta bir sınıf gövdesi dosyalar arası bölünemez ve `mixin` statik API taşıyamaz; bu yüzden `DatabaseHelper`’daki `part`+`mixin` deseni birebir uygulanmaz. Bunun yerine her domain kendi **statik sınıfı** olur (`PrefsAppSettings`, `PrefsAuthStorage`, …) ve `PrefsService` tek satırlık forwarder’larla geriye uyumu korur. Çapraz kesen orchestration (`resetAll`, `clearAuthData`, `clearAccountScopedPreferences`, `resetInMemoryCaches`) facade’de kalır. Call-site migration (65+ dosya) bu planın dışında — isteğe bağlı sonraki PR.

**Tech Stack:** Flutter / Dart 3, `shared_preferences`, `flutter_secure_storage`, `uuid`, SQLite via `DatabaseHelper`, mevcut `test/prefs_service_test.dart` güvenlik ağı.

**Context:** [2026-08-06-prefs-service-locale-injection-design.md](../specs/2026-08-06-prefs-service-locale-injection-design.md) bilinçli olarak “14 alana bölme”yi erteledi; bu plan o ertelenmiş işi yapar. Davranış değişikliği yok — saf yapısal refactor.

## Global Constraints

- Her task sonrası: `dart format .` ve `flutter analyze` temiz.
- Davranış değişikliği yok: key adları, migration fallback’leri (prefs → secure storage), cache semantiği, `metadataLocale` zorunluluğu aynı kalır.
- Public API: `PrefsService.<method>` imzaları ve isimleri **değişmez**. Call-site dokunulmaz.
- Domain sınıfları `lib/services/prefs/` altında; package-private hissi için leading underscore yok (testler doğrudan domain’e de bakabilir), ama uygulama kodu Task 1–7 boyunca yalnız `PrefsService` import etmeye devam eder.
- `CulturalPreferenceService` çağrıları yerinde kalır (`saveRating`, `clearAccountScopedPreferences`).
- Conventional Commits: `refactor(prefs): ...`
- Commit’ler küçük ve yeşil olmalı; her domain taşıması ayrı commit.
- Coverage eşiği (`lib/services`+`providers`+`models` ≥ %70) düşmemeli; mevcut testler taşınan kodu kapsamaya devam eder.

## File Structure

```
lib/services/prefs/
  app_settings.dart       # dil, tema, family, block, onboarding, genre labels, swipe/dice flags
  auth_storage.dart       # access/refresh token, user payload, last auth user id, token cache
  sync_meta.dart          # last sync/push time, sync device id
  taste_prefs.dart        # genre weights, similarity, reco telemetry/impressions/tonight,
                          # dismiss feedback, DNA cache + milestones
  library_facade.dart     # favorites, ratings, watchlist, search history, seasons → DatabaseHelper
prefs_service.dart        # ince facade + reset/clear orchestration
```

**Taşınmayan (facade’de kalan) orchestration:**

| Metot | Neden facade’de |
|-------|-----------------|
| `resetInMemoryCaches()` | auth cache + reco queue + genre weights — 3 domain’e dokunur |
| `resetAll()` | prefs + secure + `DatabaseHelper.clearAllData` |
| `clearAuthData()` | token + sync cursor + DNA |
| `clearAccountScopedPreferences()` | culture + DNA |

---

### Task 1: İskelet + kanıt dilimi (`getSelectedLanguage` / `setSelectedLanguage`)

Deseni tek küçük API ile doğrula; kalan taşımaya geçmeden yeşil commit.

**Files:**
- Create: `lib/services/prefs/app_settings.dart`
- Modify: `lib/services/prefs_service.dart` (yalnız dil getter/setter)
- Test: mevcut `test/prefs_service_test.dart` + `test/locale_provider_test.dart` (dokunma; regression)

**Interfaces:**
- Produces: `class PrefsAppSettings` with:
  - `static Future<String?> getSelectedLanguage()`
  - `static Future<void> setSelectedLanguage(String lang)`
  - `static const` key `_keyLanguage = 'selected_language'` (dosya-private)
- PrefsService:
  - `static Future<String?> getSelectedLanguage() => PrefsAppSettings.getSelectedLanguage();`
  - `static Future<void> setSelectedLanguage(String lang) => PrefsAppSettings.setSelectedLanguage(lang);`

- [ ] **Step 1: Baseline yeşil olduğunu doğrula**

```bash
flutter test test/prefs_service_test.dart test/locale_provider_test.dart
```

Expected: All tests passed.

- [ ] **Step 2: Domain sınıfını oluştur**

`lib/services/prefs/app_settings.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama ayarları (dil, tema, onboarding, blok listesi, UI bayrakları).
///
/// Public çağrı yüzeyi hâlâ [PrefsService]; bu sınıf taşıma hedefidir.
class PrefsAppSettings {
  static const _keyLanguage = 'selected_language';

  static Future<String?> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLanguage);
  }

  /// Yalnızca kalıcılaştırır. Aktif dilin sahibi `LocaleNotifier`'dır; buradan
  /// ikinci bir yazma yapılırsa iki kaynak ayrışır.
  static Future<void> setSelectedLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
  }
}
```

- [ ] **Step 3: PrefsService’i forward et**

`prefs_service.dart` üstüne ekle:

```dart
import 'prefs/app_settings.dart';
```

`getSelectedLanguage` / `setSelectedLanguage` gövdelerini silip şununla değiştir:

```dart
  static Future<String?> getSelectedLanguage() =>
      PrefsAppSettings.getSelectedLanguage();

  static Future<void> setSelectedLanguage(String lang) =>
      PrefsAppSettings.setSelectedLanguage(lang);
```

`_keyLanguage` sabitini `PrefsService` içinden kaldır (artık domain’de).

- [ ] **Step 4: Test + analyze**

```bash
dart format lib/services/prefs lib/services/prefs_service.dart
flutter analyze lib/services/prefs lib/services/prefs_service.dart
flutter test test/prefs_service_test.dart test/locale_provider_test.dart
```

Expected: analyze 0 issues; all tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/services/prefs/app_settings.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): extract PrefsAppSettings language API as split scaffold

EOF
)"
```

---

### Task 2: `PrefsAppSettings` — kalan uygulama ayarları

**Files:**
- Modify: `lib/services/prefs/app_settings.dart`
- Modify: `lib/services/prefs_service.dart`
- Test: `test/prefs_service_test.dart` (group `PrefsService.genreName` ve onboarding/tema kullananlar)

**Interfaces:**
- Moves into `PrefsAppSettings` (aynı imzalar):
  - `genreName`, `_genreNames`, `_genreNamesEn`
  - `isFamilyMode`, `setFamilyMode`
  - `blockMovie`, `isMovieBlocked`, `getBlockedKeys`
  - `getThemeMode`, `setThemeMode`
  - onboarding: `isOnboardingDone`, `setOnboardingDone`, `skipOnboarding`, `resetOnboarding`, `isOnboardingBannerDismissed`, `dismissOnboardingBanner`
  - `saveInitialGenres`, `getInitialGenres` (+ `_keyInitialGenres`, `_keyInitialGenresSavedAt`)
  - `isSwipeGuideShown`, `setSwipeGuideShown`, `isFirstTimeDice`
- PrefsService: her biri tek satır forwarder.

- [ ] **Step 1: Metotları kes-yapıştır taşı**

`prefs_service.dart` içinden yukarıdaki blokları `app_settings.dart` içine taşı. Import’lar:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

`genreName` için ek import gerekmez. Onboarding zaman damgaları mevcut mantıkla birebir kopyalanır.

- [ ] **Step 2: PrefsService forwarder’ları yaz**

Örnek kalıp (hepsi aynı stil):

```dart
  static String genreName(int id, {required String locale}) =>
      PrefsAppSettings.genreName(id, locale: locale);

  static Future<bool> isFamilyMode() => PrefsAppSettings.isFamilyMode();

  static Future<void> setFamilyMode(bool value) =>
      PrefsAppSettings.setFamilyMode(value);

  // ... block / theme / onboarding / initial genres / swipe / dice
```

- [ ] **Step 3: Doğrula**

```bash
dart format lib/services/prefs lib/services/prefs_service.dart
flutter analyze lib/services/prefs lib/services/prefs_service.dart
flutter test test/prefs_service_test.dart
```

Expected: PASS. Özellikle `PrefsService.genreName` grubu.

- [ ] **Step 4: Commit**

```bash
git add lib/services/prefs/app_settings.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): move app settings domain into PrefsAppSettings

EOF
)"
```

---

### Task 3: `PrefsAuthStorage` — token / user / last-user

**Files:**
- Create: `lib/services/prefs/auth_storage.dart`
- Modify: `lib/services/prefs_service.dart`
- Test: `test/prefs_service_test.dart` (group `PrefsService bellek ici cache`), `test/auth_provider_test.dart`, `test/auth_api_test.dart`

**Interfaces:**
- Produces: `class PrefsAuthStorage` with:
  - `_secureStorage`, `_cachedAccessToken`, `_keyAccessToken`, `_keyRefreshToken`, `_keyUserData`, `_keyLastAuthenticatedUserId`
  - `getAccessToken`, `saveTokens`, `getRefreshToken`
  - `getUserData`, `saveUserData`
  - `getLastAuthenticatedUserId`, `setLastAuthenticatedUserId`
  - `clearTokens()` — **yalnız** token + user payload + prefs migration keys (sync/DNA temizlemez)
  - `clearTokenCache()` / `resetInMemoryCaches` parçası: `_cachedAccessToken = null`
- PrefsService `clearAuthData()` orchestration:

```dart
  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors(); // Task 4’te eklenir; şimdilik inline bırakılabilir
    await PrefsTastePrefs.clearDnaCache();   // Task 5’te
  }
```

**Task 3 geçici kural:** `clearAuthData` gövdesi hâlâ `prefs_service.dart` içinde kalsın; auth kısmını `PrefsAuthStorage.clearTokens()` çağıracak şekilde ayır, sync/DNA satırları Task 4–5 gelene kadar facade’de kalsın.

- [ ] **Step 1: `auth_storage.dart` oluştur**

`prefs_service.dart` satır ~872–1020 bandındaki token/user kodunu taşı. Kritik davranışlar korunmalı:

1. Access token bellek cache
2. Secure storage önce, SharedPreferences migration fallback
3. `saveTokens` cache’i günceller
4. `clearTokens` cache’i null’lar ve hem secure hem prefs key’lerini siler

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsAuthStorage {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyAccessToken = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyUserData = 'auth_user_data';
  static const _keyLastAuthenticatedUserId = 'last_authenticated_user_id';

  static String? _cachedAccessToken;

  static void clearTokenCache() {
    _cachedAccessToken = null;
  }

  // getAccessToken / saveTokens / getRefreshToken / user data / last user /
  // clearTokens — mevcut gövdeleri birebir taşı
}
```

- [ ] **Step 2: PrefsService forward + `resetInMemoryCaches` güncelle**

```dart
import 'prefs/auth_storage.dart';

  static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();
  // ... diğer auth forwarder’lar

  @visibleForTesting
  static void resetInMemoryCaches() {
    PrefsAuthStorage.clearTokenCache();
    _recoTelemetryTail = Future<void>.value(); // Task 5’e kadar burada
    invalidateGenreWeights();                   // Task 5’e kadar burada
  }
```

`clearAuthData` içinde token temizliğini `PrefsAuthStorage.clearTokens()` yap; sync/DNA satırlarını olduğu gibi bırak.

- [ ] **Step 3: Mutasyon kontrolü (cache)**

```bash
flutter test test/prefs_service_test.dart --name "bellek"
```

Expected: PASS.

Sonra geçici olarak `PrefsAuthStorage.clearTokenCache` gövdesini boşalt, aynı testi çalıştır → FAIL, geri al → PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/prefs/auth_storage.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): extract PrefsAuthStorage for tokens and user payload

EOF
)"
```

---

### Task 4: `PrefsSyncMeta` — sync imlekleri / device id

**Files:**
- Create: `lib/services/prefs/sync_meta.dart`
- Modify: `lib/services/prefs_service.dart`, `lib/services/prefs/auth_storage.dart` (yok — facade orchestration)
- Test: `test/sync_service_test.dart`, `test/auth_sync_flow_test.dart`

**Interfaces:**
- Produces: `class PrefsSyncMeta` with:
  - `_keyLastSyncTime`, `_keyLastPushTime`, `_keySyncDeviceId`
  - `getLastSyncTime`, `setLastSyncTime`, `getLastPushTime`, `setLastPushTime`, `getSyncDeviceId`
  - `clearSyncCursors()` → `sync_last_time` + `sync_last_push_time` remove (**device id silinmez** — mevcut `clearAuthData` da device id’yi silmiyor)

- [ ] **Step 1: Dosyayı oluştur ve taşı**

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PrefsSyncMeta {
  static const _keyLastSyncTime = 'sync_last_time';
  static const _keyLastPushTime = 'sync_last_push_time';
  static const _keySyncDeviceId = 'sync_device_id';

  static Future<void> clearSyncCursors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSyncTime);
    await prefs.remove(_keyLastPushTime);
  }

  // get/set LastSyncTime, LastPushTime (push→sync fallback), getSyncDeviceId
}
```

- [ ] **Step 2: `clearAuthData` orchestration’ı bağla**

```dart
  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors();
    await clearDnaCache(); // hâlâ PrefsService veya Task 5 sonrası PrefsTastePrefs
  }
```

- [ ] **Step 3: Test**

```bash
flutter test test/sync_service_test.dart test/auth_sync_flow_test.dart test/prefs_service_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/prefs/sync_meta.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): extract PrefsSyncMeta for sync cursors and device id

EOF
)"
```

---

### Task 5: `PrefsTastePrefs` — genre weights, reco sinyalleri, DNA

En büyük ve en riskli taşıma. Tek commit’te tut; ara commit atma.

**Files:**
- Create: `lib/services/prefs/taste_prefs.dart`
- Modify: `lib/services/prefs_service.dart`
- Test: `test/prefs_service_test.dart`, `test/recommendation_engine_test.dart`, `test/similarity_test.dart`, `test/dna_milestone_test.dart`

**Interfaces:**
- Produces: `class PrefsTastePrefs` with:
  - Genre weights: `_cachedGenreWeights`, `invalidateGenreWeights`, `getGenreWeights`, `_calculateGenreWeights`, `calculateSimilarity`, `getLikedGenreIds`, `sampleLikedGenreIds`
  - Reco telemetry: `_keyRecoTelemetry`, `_recoTelemetryTail`, `_enqueueRecoTelemetry`, `_asInt`, `recordRecoOutcome`, `revertRecoOutcome`, `getRecoTelemetry`
  - Dismiss feedback: `shouldAskDismissFeedback`, `recordDismissFeedback`, `getDismissFeedback`
  - Impressions / tonight: `_getTimestampMap`, `_recordTimestamps`, `getRecoImpressions`, `recordRecoImpressions`, `getTonightHistory`, `recordTonightPick`
  - DNA: `getCachedDna`, `cacheDna`, `getLastPublishedDnaHash`, `setLastPublishedDnaHash`, `clearDnaCache`, `dnaMilestones`, `pendingDnaMilestone`, `markDnaMilestoneShown`
- Cross-import: `_calculateGenreWeights` favorites/ratings/initial genres okur → `DatabaseHelper` + `PrefsAppSettings.getInitialGenres` (+ favori API’leri Task 6’ya kadar hâlâ `PrefsService` üzerinden veya doğrudan DB). **Taşıma sırasında** genre-weight hesabı mevcut gibi `DatabaseHelper()` + `getInitialGenres` / favori listelerini çağırmalı. Favoriler hâlâ `PrefsService`’teyse:

```dart
// taste_prefs.dart içinde geçici olarak:
import '../prefs_service.dart'; // YASAK — cycle

// Bunun yerine favorites okumasını DatabaseHelper üzerinden yap
// (PrefsService.saveFavorite* zaten DB'ye yazıyor). Mevcut
// _calculateGenreWeights gövdesindeki PrefsService/DB çağrılarını
// birebir koru; eğer PrefsService static'ine referans varsa,
// Task 6 gelene kadar DatabaseHelper + PrefsAppSettings kullan.
```

**Cycle kuralı:** `prefs/*.dart` → `prefs_service.dart` import **etmez**. Facade tek yönlü bağımlıdır.

`_calculateGenreWeights` içinde bugün `getInitialGenres` / `getFavoriteMovies` varsa:
- `getInitialGenres` → `PrefsAppSettings.getInitialGenres`
- favoriler / ratings → `DatabaseHelper()` (PrefsService zaten delege ediyor)

- [ ] **Step 1: `taste_prefs.dart` oluştur, kodu taşı, cycle’sız import’lar**

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/movie.dart';
import '../db_helper.dart';
import 'app_settings.dart';

class PrefsTastePrefs {
  // ... taşınan alanlar ve metotlar
}
```

- [ ] **Step 2: PrefsService forward + cache reset**

```dart
import 'prefs/taste_prefs.dart';

  static void invalidateGenreWeights() => PrefsTastePrefs.invalidateGenreWeights();
  static Future<Map<int, double>> getGenreWeights() =>
      PrefsTastePrefs.getGenreWeights();
  // ... tüm taste forwarder’lar

  @visibleForTesting
  static void resetInMemoryCaches() {
    PrefsAuthStorage.clearTokenCache();
    PrefsTastePrefs.resetInMemoryCaches();
  }
```

`PrefsTastePrefs.resetInMemoryCaches()`:

```dart
  static void resetInMemoryCaches() {
    _recoTelemetryTail = Future<void>.value();
    invalidateGenreWeights();
  }
```

`clearAuthData` / `clearAccountScopedPreferences`:

```dart
  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors();
    await PrefsTastePrefs.clearDnaCache();
  }

  static Future<void> clearAccountScopedPreferences() async {
    await CulturalPreferenceService.clear();
    await PrefsTastePrefs.clearDnaCache();
  }
```

- [ ] **Step 3: Test paketi**

```bash
flutter test test/prefs_service_test.dart test/recommendation_engine_test.dart test/similarity_test.dart test/dna_milestone_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/prefs/taste_prefs.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): extract PrefsTastePrefs for weights, reco signals, and DNA

EOF
)"
```

---

### Task 6: `PrefsLibraryFacade` — DB delege katmanı

**Files:**
- Create: `lib/services/prefs/library_facade.dart`
- Modify: `lib/services/prefs_service.dart`
- Test: `test/prefs_service_test.dart`, `test/watchlist_provider_test.dart`, `test/top_list_provider_test.dart`

**Interfaces:**
- Produces: `class PrefsLibraryFacade` with favorites, ratings, watchlist, search history, seasons, `getStats`, `getRatedIds`, `getRatingCount`, `deleteRating`
- `saveRating` side effects korunur:

```dart
  static Future<void> saveRating({...}) async {
    await DatabaseHelper().saveRating(...);
    PrefsTastePrefs.invalidateGenreWeights();
    try {
      await CulturalPreferenceService.learnFromRatings();
    } catch (e) {
      debugPrint('Cultural preference learning failed: $e');
    }
  }
```

- [ ] **Step 1: Taşı ve forward et**

```dart
import 'package:flutter/foundation.dart';

import '../../models/movie.dart';
import '../cultural_preference_service.dart';
import '../db_helper.dart';
import 'taste_prefs.dart';

class PrefsLibraryFacade {
  static const favoritesCap = 20;
  static const _favoriteGenreBase = 3.0;
  static double favoriteRankWeight(int rank) { /* mevcut */ }

  // favorites / ratings / watchlist / search / seasons / stats
}
```

PrefsService:

```dart
  static const favoritesCap = PrefsLibraryFacade.favoritesCap; // veya forward getter
  static double favoriteRankWeight(int rank) =>
      PrefsLibraryFacade.favoriteRankWeight(rank);
  static Future<void> saveRating({...}) => PrefsLibraryFacade.saveRating(...);
```

`favoritesCap` bir `static const` — domain’de tanımla, facade’de:

```dart
  static const favoritesCap = PrefsLibraryFacade.favoritesCap;
```

Dart’ta const forward için domain const’u public olmalı (yukarıdaki gibi).

- [ ] **Step 2: Test**

```bash
flutter test test/prefs_service_test.dart test/watchlist_provider_test.dart test/top_list_provider_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/services/prefs/library_facade.dart lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): extract PrefsLibraryFacade over DatabaseHelper delegates

EOF
)"
```

---

### Task 7: Facade’i incel + `resetAll` son hali

**Files:**
- Modify: `lib/services/prefs_service.dart` (hedef: ~80–120 satır)
- Delete: yok
- Test: full prefs + auth/sync smoke

**Hedef `prefs_service.dart` iskeleti:**

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cultural_preference_service.dart';
import 'db_helper.dart';
import 'prefs/app_settings.dart';
import 'prefs/auth_storage.dart';
import 'prefs/library_facade.dart';
import 'prefs/sync_meta.dart';
import 'prefs/taste_prefs.dart';

/// Geriye uyumlu cephe. Yeni kod domain sınıflarını doğrudan çağırabilir;
/// mevcut call-site'lar PrefsService.* kullanmaya devam eder.
class PrefsService {
  // --- App settings forwards ---
  // --- Auth forwards ---
  // --- Sync forwards ---
  // --- Taste forwards ---
  // --- Library forwards ---

  @visibleForTesting
  static void resetInMemoryCaches() {
    PrefsAuthStorage.clearTokenCache();
    PrefsTastePrefs.resetInMemoryCaches();
  }

  static Future<void> resetAll() async {
    resetInMemoryCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await PrefsAuthStorage.deleteAllSecure();
    await DatabaseHelper().clearAllData();
  }

  static Future<void> clearAuthData() async {
    await PrefsAuthStorage.clearTokens();
    await PrefsSyncMeta.clearSyncCursors();
    await PrefsTastePrefs.clearDnaCache();
  }

  static Future<void> clearAccountScopedPreferences() async {
    await CulturalPreferenceService.clear();
    await PrefsTastePrefs.clearDnaCache();
  }
}
```

Task 3’te `_secureStorage.deleteAll()` `resetAll` içindeydi — bunu `PrefsAuthStorage.deleteAllSecure()` olarak auth domain’e koy:

```dart
  static Future<void> deleteAllSecure() => _secureStorage.deleteAll();
```

- [ ] **Step 1: `prefs_service.dart` içinde logic kalmadığını doğrula**

```bash
# Facade dışında SharedPreferences/SecureStorage/jsonDecode iş mantığı kalmamalı
rg "SharedPreferences|FlutterSecureStorage|jsonDecode|DatabaseHelper\(\)" lib/services/prefs_service.dart
```

Expected: yalnız `resetAll` / import satırlarında `SharedPreferences` + `DatabaseHelper`; iş metotlarında yok.

- [ ] **Step 2: Geniş test**

```bash
dart format .
flutter analyze
flutter test test/prefs_service_test.dart test/auth_provider_test.dart test/auth_sync_flow_test.dart test/sync_service_test.dart test/recommendation_engine_test.dart test/dna_milestone_test.dart test/similarity_test.dart
```

Expected: analyze clean; all passed.

- [ ] **Step 3: Commit**

```bash
git add lib/services/prefs lib/services/prefs_service.dart
git commit -m "$(cat <<'EOF'
refactor(prefs): slim PrefsService to forwarding facade after domain split

EOF
)"
```

---

### Task 8: Test dosyasını domain gruplarına ayır (opsiyonel ama önerilir)

Davranış ekleme; okunabilirlik.

**Files:**
- Modify: `test/prefs_service_test.dart` — group adlarını domain’e göre yeniden etiketle
- Create (opsiyonel): `test/prefs/app_settings_test.dart` vb. — **yalnız** mevcut testleri taşı; yeni assertion ekleme

- [ ] **Step 1:** `prefs_service_test.dart` içinde group başlıklarını güncelle:

```dart
  group('PrefsAppSettings (via PrefsService)', () { ... });
  group('PrefsAuthStorage cache (via PrefsService)', () { ... });
  group('PrefsTastePrefs genre weights (via PrefsService)', () { ... });
```

Call’lar hâlâ `PrefsService.*` — facade sözleşmesini test etmeye devam.

- [ ] **Step 2:**

```bash
flutter test test/prefs_service_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add test/prefs_service_test.dart
git commit -m "$(cat <<'EOF'
test(prefs): label prefs_service_test groups by domain after split

EOF
)"
```

---

### Task 9: Tam doğrulama + graphify notu

- [ ] **Step 1: CI parity**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: format clean; analyze 0 issues; full suite green.

- [ ] **Step 2 (opsiyonel): graphify incremental**

```bash
graphify update .
```

Beklenen: `prefs_service.dart` community’si küçülür / domain dosyaları ayrı hub olur; cohesion artışı görülebilir (garanti değil — AST gürültüsü).

- [ ] **Step 3: Commit yok** (yalnız doğrulama). Başarısızsa ilgili task’a dön.

---

## Out of Scope (bilinçli)

| Madde | Neden |
|-------|--------|
| 65 call-site’ı `PrefsAuthStorage` vb. doğrudan çağırmaya migrate | Ayrı PR; risk/churn yüksek |
| `PrefsService` → instance + mixin (`DatabaseHelper` birebir) | Statik API kırılır veya çift katman gerekir |
| Library facade’i silip call-site’ları `DatabaseHelper`’a çevirmek | Provider katmanı zaten var; ayrı tasarım |
| Key rename / storage format değişikliği | Davranış değişikliği |
| `recommendation_telemetry_service.dart` ile telemetry birleştirme | Ayrı ürün kararı |

---

## Rollback

Her task ayrı commit. Sorun olursa:

```bash
git revert <commit-sha>
```

veya domain PR birleştirilmediyse branch sil. Facade korunduğu için geri alma call-site dokunmaz.

---

## Success Criteria

1. `lib/services/prefs_service.dart` ≤ ~150 satır, yalnız forward + orchestration.
2. Beş domain dosyası `lib/services/prefs/` altında; `prefs/*` → `prefs_service.dart` import cycle yok.
3. `PrefsService` public API imza/isim değişmedi (`dart analyze` + mevcut testler).
4. `flutter analyze` clean; `flutter test` green.
5. Token migration fallback, genre-weight formülü, DNA milestone semantiği aynı.

---

## Self-Review

- Spec coverage: ertelenmiş “14 alan split” → 5 domain + facade orchestration ile karşılandı (auth+sync DNA clear çapraz kesen olarak birleşik).
- Placeholder yok: dosya yolları, imzalar, komutlar somut.
- Cycle kuralı Task 5’te açık; favori/rating okuma `DatabaseHelper` / `PrefsAppSettings` üzerinden.
- `favoritesCap` const forward not edildi.
- Önceki locale-injection davranışı (`setSelectedLanguage` yorumu, `metadataLocale`) korunuyor.
