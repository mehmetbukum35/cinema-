# cinema+

[![CI](https://github.com/mehmetbukum35/cinema-/actions/workflows/ci.yml/badge.svg)](https://github.com/mehmetbukum35/cinema-/actions/workflows/ci.yml)

**cinema+** (Ne İzlesem?) — mood-based movie/TV discovery, swipe ratings, match modes, and social recommendations. Flutter client (offline-first SQLite) + PHP REST API.

See [CHANGELOG.md](CHANGELOG.md) for release history. Store/README screenshot frames: [docs/screenshots/README.md](docs/screenshots/README.md).

## Repository layout

| Path | Purpose |
|------|---------|
| `/` | Flutter app (Android, iOS, Web, Desktop targets) |
| `/backend` | PHP 8.4+ REST API, MySQL/MariaDB, JWT auth |
| `/docs` | Project docs, [store release checklist](docs/STORE_RELEASE_CHECKLIST.md), [known issues](docs/KNOWN_ISSUES.md), [screenshots](docs/screenshots/README.md) |

## Features

- **Swipe UI** — Fast card-based rating (Awful → Amazing)
- **Search & filters** — Year, rating, language, streaming provider filters
- **Detail sheets** — Trailers, cast, seasons, watch providers, community score
- **Match modes** — Similar titles and together/genre match
- **Social** — Friends, activity feed, recommendations inbox, top public profiles
- **Offline sync** — SQLite cache with delta sync to PHP backend
- **Localization** — Turkish (default) and English
- **Sign in** — Email/password, Google, Apple (where configured)

## Setup

### Flutter

```bash
flutter pub get
```

TMDB requests go through the backend proxy (`GET /tmdb/*`). The client does **not** need a TMDB API key.

For local development, point at your API explicitly:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=WEB_PROFILE_BASE_URL=http://localhost:8000/profile
```

Without `API_BASE_URL`, the app uses the production default. In **debug/profile** builds, a console warning is printed if you hit production without an explicit define.

### Backend

```bash
cd backend
composer install
php -S localhost:8000 -t api
```

Copy `backend/src/Config.sample.php` to `backend/src/Config.php` and set DB credentials, JWT secret, and TMDB key (see backend README).

## Tests & quality

```bash
dart format .
flutter analyze
flutter test
flutter test --coverage          # → coverage/lcov.info
./tool/coverage_html.sh          # HTML report (needs `genhtml` from lcov)
cd backend && composer test
```

CI runs format check, analyze, Flutter tests with coverage gates, and PHPUnit on push/PR to `main`.

## Error monitoring

- Release builds on Android, iOS, and macOS report uncaught Flutter, platform,
  and asynchronous errors to Firebase Crashlytics. Collection stays disabled in
  debug builds.
- Every API call carries an `X-Request-ID`. The backend returns the same header
  and includes it in structured JSON error logs, so a mobile failure can be
  correlated with its server-side event.
- Backend logs redact passwords, auth headers, cookies, tokens, secrets, API
  keys, and verification/reset codes. Set `error_log_file` in the production
  `Config.php` to a path outside the web root, or leave it empty for the host's
  central PHP log sink.

## Architecture

`Flutter (Riverpod) → PHP REST API → MySQL/MariaDB`, with offline-first SQLite cache and TMDB via the backend proxy.

- **State:** Riverpod
- **Local data:** SQLite (sqflite) + SharedPreferences
- **Network:** HTTP, JWT rotation, delta sync
- **Backend modules:** Auth, Sync, Tmdb proxy, Social (split under `backend/src/Social/`)

## Tech stack

Flutter, Riverpod, sqflite, PHP 8.4, MariaDB/MySQL, TMDB (server-side), JWT auth.

## License

[MIT](LICENSE)

## Releases

- Checklist: [docs/STORE_RELEASE_CHECKLIST.md](docs/STORE_RELEASE_CHECKLIST.md)
- Screenshot capture guide: [docs/screenshots/README.md](docs/screenshots/README.md)
- Android signed AAB/APK: `.github/workflows/android-release.yml` (`workflow_dispatch` or tag `v*`)
- iOS TestFlight IPA: `.github/workflows/ios.yml` (`workflow_dispatch`)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style guides, branch protection setup, and commit conventions.
