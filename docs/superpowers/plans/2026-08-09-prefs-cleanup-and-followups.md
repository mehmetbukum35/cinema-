# Prefs Cleanup → Taste Split → ApiService Follow-ups

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefs migration’ı kilitle (test + lint + taste/library call-sites + deprecated forwarder silme); ardından `PrefsTastePrefs` alt böl; sonra `ApiService` yüzeyini gözden geçir/split et.

**Architecture:** Üç ardışık faz. Faz 1 davranış korumalı call-site/lint/cleanup. Faz 2 `taste_prefs.dart` static domain alt sınıfları (genre weights / reco signals / DNA) + ince `PrefsTastePrefs` facade veya barrel. Faz 3 `ApiService` zaten `part`+mixin; Graphify gürültüsünü azaltmak için facade incelme / dokümantasyon / gerekirse ek part ayrımı — büyük churn yok.

**Tech Stack:** Flutter/Dart 3, `analysis_options.yaml`, mevcut `lib/services/prefs/*`, `flutter_test`.

**Prior:** [prefs-service-domain-split](./2026-08-09-prefs-service-domain-split.md), [prefs-callsite-migration](./2026-08-09-prefs-callsite-migration.md).

## Global Constraints

- Davranış değişikliği yok.
- `PrefsService.clearAuthData` / `clearAccountScopedPreferences` / `resetAll` / `resetInMemoryCaches` kalıcı orchestration — silinmez, deprecate edilmez.
- `prefs/*` → `prefs_service.dart` import cycle yok.
- Her task: `dart format` + `flutter analyze` temiz + ilgili testler yeşil.
- Conventional Commits: `refactor(prefs): ...` / `refactor(api): ...` / `chore(lints): ...` / `test(prefs): ...`
- Faz 2–3, Faz 1 Success Criteria sağlanmadan başlamaz.

---

# Phase 1 — Prefs cleanup

## Task 1: Test call-sites for already-deprecated APIs (Task 4b)

**Files (from rg counts; re-verify with rg):**
- `test/auth_provider_test.dart` (~28)
- `test/auth_api_test.dart` (~15)
- `test/sync_service_test.dart` (~15)
- `test/auth_sync_flow_test.dart` (~10)
- `test/api_service_test.dart` (~9)
- `test/prefs_service_test.dart` (~14 deprecated uses — migrate to domain; keep orchestration tests on `PrefsService`)
- `test/social_api_test.dart`, `test/couch_api_test.dart`, `test/locale_provider_test.dart`, `test/swipe_widget_test.dart`

**Rule:** Replace deprecated `PrefsService.<api>` with domain target from `@Deprecated('Use X instead')` message. Keep `PrefsService.clearAuthData` / `resetAll` / `clearAccountScopedPreferences` / `resetInMemoryCaches`.

Verify empty:

```bash
rg "PrefsService\.(getAccessToken|saveTokens|getRefreshToken|getUserData|saveUserData|getLastAuthenticatedUserId|setLastAuthenticatedUserId|getLastSyncTime|setLastSyncTime|getLastPushTime|setLastPushTime|getSyncDeviceId|getSelectedLanguage|setSelectedLanguage|getThemeMode|setThemeMode|isFamilyMode|setFamilyMode|genreName|blockMovie|isMovieBlocked|getBlockedKeys|isOnboardingDone|setOnboardingDone|skipOnboarding|resetOnboarding|isOnboardingBannerDismissed|dismissOnboardingBanner|saveInitialGenres|getInitialGenres|isSwipeGuideShown|setSwipeGuideShown|isFirstTimeDice)\b" test --glob "*.dart"
```

Expected: no matches.

- [ ] **Step 1:** Migrate auth/sync test files + api tests  
- [ ] **Step 2:** Migrate prefs_service_test deprecated groups to domains; keep cache/resetAll groups on PrefsService  
- [ ] **Step 3:**

```bash
flutter analyze
flutter test
```

- [ ] **Step 4: Commit**

```bash
git commit -m "test(prefs): migrate deprecated PrefsService call-sites in tests"
```

---

## Task 2: Enable `deprecated_member_use_from_same_package`

**Files:**
- Modify: `analysis_options.yaml`

```yaml
linter:
  rules:
    # ... existing ...
    - deprecated_member_use_from_same_package
```

- [ ] **Step 1:** Add rule  
- [ ] **Step 2:** `flutter analyze` — 0 issues (Task 1 sonrası lib+test temiz olmalı). Kalan ihlal varsa Task 1’e dön.  
- [ ] **Step 3: Commit**

```bash
git commit -m "chore(lints): enable deprecated_member_use_from_same_package"
```

---

## Task 3: Taste / library call-site migration (lib/)

**Targets:**

| Domain | APIs (non-exhaustive — rg to complete) |
|--------|------------------------------------------|
| `PrefsTastePrefs` | getGenreWeights, invalidateGenreWeights, calculateSimilarity, getLikedGenreIds, sampleLikedGenreIds, reco telemetry/impressions/tonight/dismiss, DNA cache/milestones, revertRecoOutcome, recordRecoOutcome |
| `PrefsLibraryFacade` | saveRating, getRating, deleteRating, deleteComment, getCommentedRatings, getRatedIds, getRatingCount, getStats, watchlist*, favorites*, search history*, seasons*, favoriteRankWeight, favoritesCap, mergeFavorite* |

**Heavy files:** `browse_screen.dart`, `movie_detail_sheet.dart`, `recommendation_engine.dart`, `watchlist_provider.dart`, `top_list_provider.dart`, `swipe_provider.dart`, `taste_dna_service.dart`, `sync_service.dart` (invalidate + DNA hash), screens listed by prior rg.

**Do not migrate:** orchestration four on PrefsService.

After migration, deprecate the emptied taste/library forwarders on `PrefsService` (same pattern as prior plan Task 4).

Then migrate **test** call-sites for those newly deprecated APIs (or in same commit if small).

Verify:

```bash
rg "PrefsService\.(saveRating|getRating|getGenreWeights|addToWatchlist|getWatchlist|getFavorite|cacheDna|getCachedDna|invalidateGenreWeights|calculateSimilarity|sampleLikedGenreIds|getRecoTelemetry|favoritesCap|favoriteRankWeight)\b" lib --glob "*.dart"
```

Expected: no matches (extend pattern to full emptied set).

- [ ] **Step 1:** Providers + services (reco, dna, sync invalidate)  
- [ ] **Step 2:** Screens  
- [ ] **Step 3:** `@Deprecated` on emptied taste/library forwarders in `prefs_service.dart`  
- [ ] **Step 4:** Fix test deprecations until `flutter analyze` clean  
- [ ] **Step 5:**

```bash
flutter test
git commit -m "refactor(prefs): route taste and library call-sites to domain classes"
```

(Split into 2 commits if diff huge: migration then deprecate+tests.)

---

## Task 4: Delete emptied deprecated forwarders

**Files:** `lib/services/prefs_service.dart`

Remove every `@Deprecated` method/const forwarder that has **zero** remaining references in `lib/` and `test/` (rg before delete). Keep orchestration four + any still-referenced forwarders (should be none if Task 3 complete).

Target end state: `prefs_service.dart` ≈ orchestration-only (~40–80 lines) OR orchestration + thin re-exports only if needed — prefer delete.

- [ ] **Step 1:** rg each deprecated symbol; delete unused  
- [ ] **Step 2:** `flutter analyze` + `flutter test`  
- [ ] **Step 3:** Optional `graphify update .` — expect `PrefsService` degree/community shrink  
- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(prefs): remove emptied deprecated PrefsService forwarders"
```

### Phase 1 Success Criteria

1. No deprecated PrefsService auth/sync/settings/taste/library uses in lib/ or test/ (except intentional ignore — none preferred).  
2. `deprecated_member_use_from_same_package` enabled; analyze clean.  
3. `PrefsService` only orchestration (and maybe 0 forwarders).  
4. Full test suite green.

---

# Phase 2 — `PrefsTastePrefs` split (~437 lines)

> Start only after Phase 1 Success Criteria.

**Suggested files:**

```
lib/services/prefs/taste/
  genre_weights.dart    # cache, calculate, similarity, liked sampling; resetOnboarding/saveInitialGenres side effects
  reco_signals.dart     # telemetry, impressions, tonight, dismiss feedback
  dna_prefs.dart        # DNA cache + milestones
taste_prefs.dart        # thin facade forwarding to the three (keep PrefsTastePrefs name for call-sites)
```

Static classes or part/mixin — **static classes** (match prefs domain pattern; no tear-offs).

Tasks (detail when Phase 1 done):
1. Extract `PrefsGenreWeights` + forward from `PrefsTastePrefs`  
2. Extract `PrefsRecoSignals`  
3. Extract `PrefsDnaPrefs`  
4. Slim `PrefsTastePrefs` + tests + analyze  

Commit prefix: `refactor(prefs): split taste_prefs into ...`

---

# Phase 3 — `ApiService` surface

> After Phase 2. Prefer investigation before big rewrite.

**Facts:** Already `part` + mixins (`AuthApi`, `CouchApi`, `SocialApi`, `SyncApi`, `RecommendationApi`). Graphify Community 1 cohesion 0.02 is partly AST noise.

**Plan of record:**
1. Audit: line counts, what still lives in `api_service.dart` vs parts  
2. Move leftover methods into existing mixins / new part if any orphan cluster  
3. Do **not** invent a second facade layer unless audit shows clear win  
4. Update docs/comments; optional graphify update  

Commit prefix: `refactor(api): ...`

---

## Out of Scope (all phases)

- Changing storage keys / sync protocol  
- Renaming `PrefsService` orchestration API  
- Neo4j/wiki graphify exports  

## Self-Review

- Lint enable after test migration (Task 1→2 order).  
- Forwarder delete only after taste/library migration + deprecate + test clean.  
- Phase 2/3 gated on Phase 1.  
- clearAuthData trap documented.
