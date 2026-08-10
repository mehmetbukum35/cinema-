# Known issues

Constraints we've hit, confirmed, and cannot close from inside this repo. Each
entry says how to re-check it, so nobody has to rediscover the finding.

---

## The KGP build warning is half false positive, half blocked on one plugin

**Status:** waiting on `sign_in_with_apple` · **Severity:** cosmetic today, future build break
**Last verified:** 2026-08-10 (Flutter 3.44.9, AGP 9.0.1)

Every Android build prints:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
flutter_timezone, sign_in_with_apple
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

**Nothing is broken and nothing is at risk right now.** `android/gradle.properties`
carries the two flags Flutter's [migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
prescribes for exactly this situation, and AGP 9 honours them:

```properties
android.newDsl=false
android.builtInKotlin=false
```

There is no flag that silences the warning — printing it *is* the mechanism
Flutter uses to push app developers to nudge plugin authors.

### The two plugins are not in the same state

| Plugin | Migrated? | Evidence |
|---|---|---|
| `flutter_timezone` 5.1.0 | **yes** | applies KGP only inside `if (agpMajor < 9 \|\| !builtInKotlinEnabled)` |
| `sign_in_with_apple` 8.1.0 | **no** | `apply plugin: 'kotlin-android'` unconditionally, `android/build.gradle:25` |

`flutter_timezone` is a **false positive**. Its maintainer closed
[#61](https://github.com/tjarvstrand/flutter_timezone/issues/61) and
[#63](https://github.com/tjarvstrand/flutter_timezone/issues/63) with: the
warning "triggers based on a regex text search which doesn't take into account
that the application is conditional." Nothing to do there — do not file another
issue.

`sign_in_with_apple` is the real blocker.
[#492](https://github.com/aboutyou/dart_packages/issues/492) and
[#488](https://github.com/aboutyou/dart_packages/issues/488) are open and the
maintainers have a CI job planned against Flutter 3.47
([#493](https://github.com/aboutyou/dart_packages/issues/493)), so it is on
their radar — it just hasn't shipped.

### Why we can't just flip the flag

Setting `android.builtInKotlin=true` would silence `flutter_timezone` (its
conditional stops firing). **Tried it on 2026-08-10 — the build fails:**

```
The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin
support since AGP 9.0.
Applying the Kotlin Android Plugin (KGP) was unsuccessful. KGP was not found
on the classpath.
```

AGP 9 registers Kotlin itself when the flag is on, and `sign_in_with_apple`
then applies `kotlin-android` on top of it. So the flag can only be flipped
**after** `sign_in_with_apple` ships its migration — one change unblocks both.

### Re-check when Flutter warns louder, or quarterly

```bash
flutter pub outdated | grep sign_in_with_apple
```

If a newer version appears, bump it, then try the flag and build:

```bash
# android/gradle.properties: android.builtInKotlin=true
flutter build apk --debug
```

A clean build with no KGP warning means it's closed — delete this entry and
keep the flag on.

### If Flutter's deadline arrives before upstream ships

`sign_in_with_apple` has no drop-in replacement — Sign in with Apple is an App
Store requirement wherever third-party sign-in is offered, so we can't simply
remove it (`lib/providers/auth/social_sign_in.dart`, `account.dart`). The
fallback would be a `dependency_overrides` entry pointing at a fork with the
two `build.gradle` lines made conditional, mirroring what `flutter_timezone`
already does. Small patch, but it puts a fork on us — only worth it under a
hard deadline.
