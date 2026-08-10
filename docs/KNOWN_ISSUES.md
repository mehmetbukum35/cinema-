# Known issues

Constraints we've hit, confirmed, and cannot close from inside this repo. Each
entry says how to re-check it, so nobody has to rediscover the finding.

---

## Two Android plugins still apply the Kotlin Gradle Plugin

**Status:** blocked upstream · **First seen:** 2026-08-10 · **Severity:** future build break

Every Android build prints:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
flutter_timezone, sign_in_with_apple
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Flutter is moving to [Built-in Kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers);
plugins that declare their own KGP classpath will stop building.

**Why we can't fix it:** both packages are already pinned to their newest
published release, and both still apply KGP there:

| Package | Ours | Latest on pub.dev | Still applies KGP? |
|---|---|---|---|
| `flutter_timezone` | 5.1.0 | 5.1.0 | yes — `android/build.gradle:13,34` |
| `sign_in_with_apple` | 8.1.0 | 8.1.0 | yes — `android/build.gradle:13,25` |

There is no version to upgrade to. The fix has to land upstream.

**Re-check when Flutter warns louder, or quarterly:**

```bash
flutter pub outdated | grep -E "flutter_timezone|sign_in_with_apple"
```

If either shows a newer version, bump it in `pubspec.yaml` and confirm the
warning is gone:

```bash
flutter build apk --debug 2>&1 | grep -i "kotlin gradle plugin"
```

Silence means it's closed — delete this entry.

**If upstream stalls and Flutter's deadline arrives:** `flutter_timezone` is
the easier of the two to drop — the whole dependency is one call,
`FlutterTimezone.getLocalTimezone()` at `lib/services/notification_service.dart:72`,
resolving the device timezone for scheduled notifications; `package:timezone`
plus a small platform channel covers it. `sign_in_with_apple` has
no comparable escape hatch; Sign in with Apple is an App Store requirement
wherever third-party sign-in is offered, so that one has to be waited out.
