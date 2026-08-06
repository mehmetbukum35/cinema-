# Store release checklist — cinema+ (Ne İzlesem?)

Use this before the first Play Console / App Store Connect upload and again on every store-facing version bump.

Current app version in `pubspec.yaml`: check `version:` (`1.0.0+1` = name `1.0.0`, build `1`). CI overrides **build number** with `$GITHUB_RUN_NUMBER` on release workflows.

---

## 1. Screenshots (blocking for listing)

See [screenshots/README.md](screenshots/README.md) for capture sizes and filenames.

- [ ] Phone frames captured (TR and/or EN UI as shipped)
- [ ] Required surfaces present: Browse, Swipe, Search, Social, Detail, Profile
- [ ] No debug banners, test accounts, or placeholder API errors in frame
- [ ] Files committed under `docs/screenshots/` (or linked CDN) and README table updated
- [ ] Play: phone set uploaded; tablet optional
- [ ] App Store: 6.7" and/or 6.5" iPhone set; iPad if you ship tablet

---

## 2. Listing copy

- [ ] App name / subtitle within store limits
- [ ] Short description + full description (TR primary; EN if dual listing)
- [ ] Privacy policy URL (live HTTPS)
- [ ] Support URL or email
- [ ] Category / content rating questionnaire completed
- [ ] Data safety / App Privacy answers match real behavior (analytics, Crashlytics, account, sync)

---

## 3. Secrets & signing (CI)

### Android (`android-release.yml`)

- [ ] `ANDROID_KEYSTORE_BASE64`
- [ ] `ANDROID_KEYSTORE_PASSWORD`
- [ ] `ANDROID_KEY_PASSWORD`
- [ ] `ANDROID_KEY_ALIAS`
- [ ] Workflow produces **non-debug** APK (job verifies) + AAB artifact
- [ ] Trigger: `workflow_dispatch` or tag `v*`

### iOS TestFlight (`ios.yml`)

- [ ] `IOS_DIST_CERT_P12` + `IOS_DIST_CERT_PASSWORD`
- [ ] `IOS_PROVISIONING_PROFILE`
- [ ] `APPSTORE_API_KEY_ID` / `APPSTORE_ISSUER_ID` / `APPSTORE_API_PRIVATE_KEY`
- [ ] `ios/ExportOptions.plist` matches App Store / TestFlight export
- [ ] Trigger: `workflow_dispatch` → IPA upload to TestFlight

---

## 4. Build & version hygiene

- [ ] `pubspec.yaml` marketing version bumped when user-facing
- [ ] Tag `vX.Y.Z` if using Android tag path (optional alongside dispatch)
- [ ] Release notes drafted for Play + TestFlight “What to Test”
- [ ] Production `API_BASE_URL` / backend health confirmed
- [ ] Crashlytics enabled on release (debug stays off)

---

## 5. Smoke on a release candidate

Install the CI artifact (AAB→internal track or TestFlight build), then:

- [ ] Cold start + login (email and/or Google/Apple as configured)
- [ ] Browse rails load; tonight pick / personal rail OK
- [ ] Swipe rate persists offline then syncs
- [ ] Search + filters + results
- [ ] Library (watchlist + rated)
- [ ] Social: friend request / feed (if account has data)
- [ ] Profile: Top 20, cultural prefs, DNA when eligible
- [ ] Locale switch TR ↔ EN without wrong metadata titles
- [ ] Sign-out / wipe does not leak previous user’s prefs

---

## 6. Store upload

### Google Play

- [ ] Internal testing track first (AAB from `android-release` artifact)
- [ ] Closed/open testing as needed
- [ ] Production rollout (staged % optional)
- [ ] Store listing + screenshots attached to the release

### Apple

- [ ] TestFlight external/internal groups smoke the build
- [ ] App Store version created; build selected
- [ ] Screenshots + description attached
- [ ] Submit for review

---

## 7. After ship

- [ ] Tag / GitHub Release notes point at CHANGELOG
- [ ] Monitor Crashlytics + backend error logs for 24–48h
- [ ] Mark screenshot TODO done in [screenshots/README.md](screenshots/README.md)

---

## Out of scope here (repo hygiene, not store blockers)

Tracked in [YOL_HARITASI_test_ve_repo.md](YOL_HARITASI_test_ve_repo.md): branch protection, Dependabot, commitlint.
