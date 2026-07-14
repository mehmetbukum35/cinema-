# cinema+

[![CI](https://github.com/mehmetbukum35/cinema-/actions/workflows/ci.yml/badge.svg)](https://github.com/mehmetbukum35/cinema-/actions/workflows/ci.yml)

**cinema+** (Ne İzlesem?) is a Flutter mobile app with a PHP backend for movie and TV discovery, swipe-based ratings, social features, and offline-first sync.

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Repository layout

| Path | Purpose |
|------|---------|
| `/` | Flutter app (Android, iOS, Web, Desktop targets) |
| `/backend` | PHP 8.4+ REST API, MySQL/MariaDB, JWT auth |
| `/docs` | Project docs and [screenshots placeholder](docs/screenshots/README.md) |

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

Copy `backend/config.example.php` to `backend/config.php` and set DB credentials, JWT secret, and TMDB key (see backend README).

## Tests & quality

```bash
dart format .
flutter analyze
flutter test
cd backend && composer test
```

CI runs format check, analyze, Flutter tests with coverage, and PHPUnit on push/PR to `main`.

## Architecture

- **State:** Riverpod
- **Local data:** SQLite (sqflite) + SharedPreferences
- **Network:** HTTP, JWT rotation, delta sync
- **Backend modules:** Auth, Sync, Tmdb proxy, Social (split under `backend/src/Social/`)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for style guides, branch protection setup, and commit conventions.
