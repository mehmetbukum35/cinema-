# Prefs Call-Site Migration & Facade Thinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefs domain call-site’larını doğrudan domain sınıflarına taşı; `PrefsService` tear-off’larını gerçek forwarder’lara çevirip `@Deprecated` + DartDoc ile aşamalı geçiş sağla; Graphify’deki suni facade hub’ını consumer tarafında çöz.

**Architecture:** Önce tear-off (`static final x = Domain.x`) → method forwarder dönüşümü (aksi halde `@Deprecated`/`///` konamaz — I-1). Sonra hot-path (`PrefsAuthStorage`, `PrefsSyncMeta`) ve app-settings (`PrefsAppSettings` / cache-safe taste wrappers) migration. Çapraz orchestration (`clearAuthData`, `clearAccountScopedPreferences`, `resetAll`, `resetInMemoryCaches`) **facade’de kalır ve deprecate edilmez**. Taste/library call-site’ları ve `api_service` split bu planın dışında.

**Tech Stack:** Flutter / Dart 3, mevcut `lib/services/prefs/*`, Riverpod providers, `flutter_test`.

**Prior art:** [2026-08-09-prefs-service-domain-split.md](./2026-08-09-prefs-service-domain-split.md); final review I-1 (tear-offs) / I-2 (onboarding in taste).

## Global Constraints

- Davranış değişikliği yok: key’ler, token migration fallback, sync cursor semantiği, genre-weight invalidation aynı.
- `clearAuthData` / `clearAccountScopedPreferences` / `resetAll` / `resetInMemoryCaches` → **yalnızca `PrefsService`** (orchestration). Bunları `PrefsAuthStorage.clearTokens` ile değiştirmek DNA/sync cursor sızıntısı yaratır — yasak.
- `saveInitialGenres` / `resetOnboarding` → **`PrefsTastePrefs`** (genre-weight invalidation). Ham `PrefsAppSettings` varyantlarına migrate etme (I-2).
- `prefs/*` → `prefs_service.dart` import cycle yok.
- Her task: `dart format` + `flutter analyze` temiz; ilgili testler yeşil.
- Conventional Commits: `refactor(prefs): ...`
- Test dosyalarında `PrefsService` kullanımı bu planda zorunlu migrate değil; production `lib/` öncelikli. Deprecate sonrası analyzer `deprecated_member_use` uyarılarını lib’de sıfırla.
- Bu PR’da forwarder’ları **silme** — sadece deprecate. Silme ayrı follow-up.

## File Structure (locked)

| Dosya | Rol |
|-------|-----|
| `lib/services/prefs_service.dart` | Method forwarders + orchestration; migrate edilen API’lerde `@Deprecated` |
| `lib/services/prefs/auth_storage.dart` | Token/user — hot path target |
| `lib/services/prefs/sync_meta.dart` | Sync cursors/device id — hot path target |
| `lib/services/prefs/app_settings.dart` | Dil/tema/family/block/UI flags |
| `lib/services/prefs/taste_prefs.dart` | `saveInitialGenres` / `resetOnboarding` (cache-safe) |
| Call-sites | Aşağıdaki task listeleri |

**Orchestration — deprecate etme (kalıcı facade API):**

```dart
PrefsService.clearAuthData()
PrefsService.clearAccountScopedPreferences()
PrefsService.resetAll()
PrefsService.resetInMemoryCaches()
```

---

### Task 0: Tear-off → method forwarder (ön koşul)

**Files:**
- Modify: `lib/services/prefs_service.dart` (tüm `static final` domain yönlendirmeleri)
- Test: `test/prefs_service_test.dart` (regression — imza/davranış)

**Interfaces:**
- Her domain API için kalıp:

```dart
/// Prefer [PrefsAuthStorage.getAccessToken].
static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();
```

- `static const dnaMilestones` / `favoritesCap` const forward olduğu gibi kalabilir (`static const x = Domain.x`).
- `@visibleForTesting` `resetInMemoryCaches` gövdesi aynı; üzerine DartDoc geri ekle (test izolasyonu gerekçesi — split öncesi metin).

- [ ] **Step 1: Baseline**

```bash
flutter test test/prefs_service_test.dart
```

Expected: All passed.

- [ ] **Step 2: Dönüştür**

`prefs_service.dart` içindeki her `static final name = Domain.name;` satırını method forwarder yap. Örnekler:

```dart
  static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) => PrefsAuthStorage.saveTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  static String genreName(int id, {required String locale}) =>
      PrefsAppSettings.genreName(id, locale: locale);
```

Named params / opsiyonel params domain imzasıyla **birebir** eşleşmeli — tear-off’un taşıdığı imzayı `auth_storage.dart` / diğer domain dosyalarından kopyala.

`static const favoritesCap` / `static const dnaMilestones` dokunma.

- [ ] **Step 3: Doğrula**

```bash
dart format lib/services/prefs_service.dart
flutter analyze lib/services/prefs_service.dart
flutter test test/prefs_service_test.dart test/auth_provider_test.dart test/auth_api_test.dart
```

Expected: analyze 0 issues; tests pass. Call-site’lar `PrefsService.getAccessToken()` olarak çalışmaya devam eder (tear-off → method geçişi source-compatible).

- [ ] **Step 4: Commit**

```bash
git add lib/services/prefs_service.dart
git commit -m "refactor(prefs): replace tear-offs with method forwarders for deprecation support"
```

---

### Task 1: Hot path — Auth storage call-sites

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `lib/services/api/auth_api.dart`
- Modify: `lib/providers/auth/session.dart`
- Modify: `lib/providers/auth/account.dart`
- Modify: `lib/services/sync_service.dart` (yalnız `getUserData` satırı — auth payload)
- Import: `package:ne_izlesem/services/prefs/auth_storage.dart` (veya relative `prefs/auth_storage.dart` — dosyanın mevcut import stiline uy)

**Migrate (PrefsService → PrefsAuthStorage):**

| Call | Target |
|------|--------|
| `getAccessToken` | `PrefsAuthStorage.getAccessToken` |
| `getRefreshToken` | `PrefsAuthStorage.getRefreshToken` |
| `saveTokens` | `PrefsAuthStorage.saveTokens` |
| `getUserData` | `PrefsAuthStorage.getUserData` |
| `saveUserData` | `PrefsAuthStorage.saveUserData` |
| `getLastAuthenticatedUserId` | `PrefsAuthStorage.getLastAuthenticatedUserId` |
| `setLastAuthenticatedUserId` | `PrefsAuthStorage.setLastAuthenticatedUserId` |

**Do NOT migrate (stay PrefsService):**

- `clearAuthData`
- `clearAccountScopedPreferences`
- `resetAll`

Concrete map (lib, current):

- `api_service.dart`: getAccessToken×2, getRefreshToken×2, getUserData×2, saveTokens×1; **clearAuthData×1 → PrefsService**
- `api/auth_api.dart`: getRefreshToken×1; **clearAuthData×3 → PrefsService**
- `providers/auth/session.dart`: token/user/lastUser/saveTokens/saveUserData; **clearAuthData / clearAccountScopedPreferences / resetAll → PrefsService**; sync cursors → Task 2
- `providers/auth/account.dart`: saveUserData×3
- `sync_service.dart`: getUserData×1

- [ ] **Step 1: api_service + auth_api**

Import ekle, token/user çağrılarını `PrefsAuthStorage` yap; `clearAuthData` satırlarını `PrefsService` bırak.

- [ ] **Step 2: auth session/account + sync getUserData**

Aynı kural.

- [ ] **Step 3: Test**

```bash
flutter analyze lib/services/api_service.dart lib/services/api/auth_api.dart lib/providers/auth lib/services/sync_service.dart
flutter test test/auth_provider_test.dart test/auth_api_test.dart test/api_service_test.dart test/auth_sync_flow_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/api_service.dart lib/services/api/auth_api.dart lib/providers/auth/session.dart lib/providers/auth/account.dart lib/services/sync_service.dart
git commit -m "refactor(prefs): route auth hot path through PrefsAuthStorage"
```

---

### Task 2: Hot path — Sync meta call-sites

**Files:**
- Modify: `lib/services/sync_service.dart`
- Modify: `lib/services/api/sync_api.dart`
- Modify: `lib/providers/auth/session.dart` (`setLastSyncTime` / `setLastPushTime`)
- Modify: `lib/screens/profile/widgets/sync_header_action.dart`
- Modify: `lib/services/recommendation_experiment_service.dart` (`getSyncDeviceId`)

**Migrate → `PrefsSyncMeta`:**

- `getLastSyncTime` / `setLastSyncTime`
- `getLastPushTime` / `setLastPushTime`
- `getSyncDeviceId`

Import: `prefs/sync_meta.dart`.

- [ ] **Step 1: Replace all listed call-sites**

- [ ] **Step 2: Test**

```bash
flutter analyze lib/services/sync_service.dart lib/services/api/sync_api.dart lib/providers/auth/session.dart lib/screens/profile/widgets/sync_header_action.dart lib/services/recommendation_experiment_service.dart
flutter test test/sync_service_test.dart test/auth_sync_flow_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/services/sync_service.dart lib/services/api/sync_api.dart lib/providers/auth/session.dart lib/screens/profile/widgets/sync_header_action.dart lib/services/recommendation_experiment_service.dart
git commit -m "refactor(prefs): route sync cursors through PrefsSyncMeta"
```

---

### Task 3: App settings (+ cache-safe onboarding) call-sites

**Files (representative — `rg PrefsService\\.(getSelectedLanguage|setSelectedLanguage|getThemeMode|...)` ile doğrula):**
- `lib/main.dart` — language, onboarding done
- `lib/services/providers.dart` — language, theme
- `lib/screens/profile/widgets/family_mode_card.dart`
- `lib/services/tmdb_service.dart`, `lib/services/tmdb/lists.dart`, `lib/services/tmdb/discover.dart` — family mode
- `lib/screens/browse_screen.dart`, `lib/providers/couch_provider.dart`, `lib/screens/movie_detail/detail_actions.dart` — block/keys
- `lib/screens/browse/onboarding_banner.dart`
- `lib/screens/onboarding_screen.dart`, `lib/screens/onboarding/genre_step.dart`
- `lib/screens/swipe_screen.dart`, `lib/screens/swipe/widgets/gesture_guide_overlay.dart`
- `lib/widgets/app_top_bar.dart` — dice
- `lib/screens/profile_screen.dart` — **resetOnboarding → PrefsTastePrefs**
- Genre label call-sites (`genreName`): `wrapped_modal`, `stats_cards`, `taste_dna_presenter`, `match_together_body`, `genre_step`, …

**Migrate rules:**

| API | Target |
|-----|--------|
| language, theme, family, block*, swipe guide, dice, onboarding banner, `isOnboardingDone` / `setOnboardingDone` / `skipOnboarding`, `getInitialGenres`, `genreName` | `PrefsAppSettings` |
| `saveInitialGenres` | **`PrefsTastePrefs.saveInitialGenres`** |
| `resetOnboarding` | **`PrefsTastePrefs.resetOnboarding`** |

- [ ] **Step 1: providers + main + family/TMDB**

- [ ] **Step 2: onboarding / browse / swipe / genreName UI**

- [ ] **Step 3: Test**

```bash
flutter analyze lib/
flutter test test/locale_provider_test.dart test/prefs_service_test.dart test/app_flow_test.dart
```

Expected: PASS. `lib/` içinde migrate edilen semboller için `PrefsService.<that>` kalmamalı (orchestration hariç).

Verify:

```bash
rg "PrefsService\.(getAccessToken|saveTokens|getRefreshToken|getUserData|saveUserData|getLastAuthenticatedUserId|setLastAuthenticatedUserId|getLastSyncTime|setLastSyncTime|getLastPushTime|setLastPushTime|getSyncDeviceId|getSelectedLanguage|setSelectedLanguage|getThemeMode|setThemeMode|isFamilyMode|setFamilyMode|genreName|saveInitialGenres|resetOnboarding)" lib --glob "*.dart"
```

Expected: no matches (or only comments).

- [ ] **Step 4: Commit**

```bash
git add lib/
git commit -m "refactor(prefs): route app settings call-sites to domain classes"
```

---

### Task 4: `@Deprecated` + DartDoc on migrated forwarders

**Files:**
- Modify: `lib/services/prefs_service.dart` only

**Rule:** Task 1–3’te lib call-site’ı kalmamış her forwarder’a:

```dart
  /// Prefer [PrefsAuthStorage.getAccessToken].
  @Deprecated('Use PrefsAuthStorage.getAccessToken instead')
  static Future<String?> getAccessToken() => PrefsAuthStorage.getAccessToken();
```

**Deprecate etme:**
- `clearAuthData`, `clearAccountScopedPreferences`, `resetAll`, `resetInMemoryCaches`
- Hâlâ lib’den yoğun kullanılan taste/library forwarder’ları (`saveRating`, `getGenreWeights`, `addToWatchlist`, …) — bu plan onları migrate etmedi; deprecate **edilmez** (aksi halde lib dışı + test gürültüsü). Yalnızca Task 1–3’te boşaltılan API’ler.

- [ ] **Step 1: Annotate emptied forwarders**

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/
```

Expected: `deprecated_member_use` **lib/** içinde 0 (production migrate tamam). Testlerde uyarı olabilir — bu planda test migrate zorunlu değil; istersen `deprecated_member_use_from_same_package` ignore etme, testleri ayrı commit’te temizle (opsiyonel Task 4b).

- [ ] **Step 3: Commit**

```bash
git add lib/services/prefs_service.dart
git commit -m "refactor(prefs): deprecate migrated PrefsService forwarders"
```

---

### Task 4b (optional): Test call-sites for deprecated APIs

**Files:** `test/**/*.dart` that still call deprecated `PrefsService` auth/sync/settings APIs.

- [ ] Replace with domain imports where straightforward (`prefs_service_test` facade contract testleri **PrefsService**’te kalabilir — facade sözleşmesini test ederler; deprecate analyzer’ı için `// ignore:` veya facade testlerini non-deprecated orchestration + domain unit testlerine böl).

- [ ] `flutter test` + commit `test(prefs): migrate deprecated PrefsService call-sites in tests`

---

### Task 5: Verification + graphify note

- [ ] **Step 1:**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: clean; all tests passed.

- [ ] **Step 2 (optional):**

```bash
graphify update .
```

Beklenti: `PrefsService` community/degree **kısmen** düşer (consumer `references` azalır). `defines` hub’ı forwarder’lar silinene kadar sürer — bu plan silmez; follow-up.

- [ ] **Step 3:** Commit yok (verification only) veya docs-only not.

---

## Out of Scope

| Madde | Neden |
|-------|--------|
| `PrefsService` forwarder silme | Ayrı PR; deprecate süresi |
| Taste/library call-site migration | Geniş yüzey; sonraki plan |
| `taste_prefs` alt bölme | Ayrı plan |
| `api_service` split | Ayrı plan; zaten mixin’li |
| `clearAuthData`’yı parçalayıp call-site’lara yayma | Davranış riski |

## Success Criteria

1. Task 0: tüm domain yönlendirmeleri method forwarder (tear-off yok, const hariç).
2. Auth/sync/settings hot path lib call-site’ları domain sınıflarında.
3. Orchestration yalnız `PrefsService`’te; `clearAuthData` semantiği bozulmamış.
4. Migrate edilen forwarder’larda `@Deprecated` + `Prefer [Domain.method]` DartDoc.
5. `flutter analyze` / `flutter test` yeşil.

## Self-Review

- I-1 karşılandı: Task 0 önce.
- I-2 karşılandı: `saveInitialGenres` / `resetOnboarding` → TastePrefs.
- `clearAuthData` tuzakları Task 1’de açık.
- Silme bilinçli olarak out of scope.
