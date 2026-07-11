# cinema+ — Agent & Contributor Rules

This file guides AI agents and human contributors working on **cinema+** (Flutter + PHP monorepo).

## Project overview

- **Frontend:** Flutter (Riverpod), offline-first SQLite cache, TMDB via backend proxy
- **Backend:** PHP 8.4 REST API, MySQL/MariaDB, JWT auth, social features
- **Locales:** Turkish (default) and English via `AppLocalizations.get(key)`

## Repository layout

| Path | Purpose |
|------|---------|
| `lib/screens/` | Screen orchestrators; large UIs split into subfolders (`profile/`, `social/`, `browse/`, `match/`, `movie_detail/`) |
| `lib/providers/` | Riverpod state (business logic) |
| `lib/services/` | API, DB, sync, notifications, localization wrapper |
| `lib/l10n/` | Locale string maps (`en.dart`, `tr.dart`) |
| `test/` | Flutter unit & widget tests |
| `backend/src/` | PHP API logic |
| `backend/tests/` | PHPUnit tests |
| `.github/workflows/` | CI (`ci.yml`), iOS (`ios.yml`), Android release (`android-release.yml`) |

## Code style

### Dart / Flutter

- Match existing patterns: Riverpod `ConsumerWidget` / `ConsumerStatefulWidget`, `context.c` theme extension
- **Screen refactor pattern:** thin orchestrator in `*_screen.dart`; widgets in `screens/<area>/`
- Run `dart format .` and `flutter analyze` before committing
- Minimize scope — no drive-by refactors
- Prefer extending existing helpers over new abstractions

### PHP

- PHP 8.4+, modular classes under `backend/src/`
- Run `backend/vendor/bin/phpunit` when touching backend

### Localization

- Add keys to **both** `lib/l10n/en.dart` and `lib/l10n/tr.dart`
- Use `AppLocalizations.of(context)?.get('key') ?? 'fallback'` in UI

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <summary in imperative mood>
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `ci`

Examples:

- `feat(notifications): schedule release-day watchlist reminders`
- `refactor(match): split match_screen into match/ modules`
- `test(widget): add smoke tests for profile and browse screens`

## Testing requirements

Before pushing changes that touch Dart:

```bash
flutter analyze
flutter test
```

If backend changed:

```bash
cd backend && composer test
```

Widget smoke tests exist for: profile, browse, social, movie detail, swipe, main shell.

## CI

- **ci.yml** — runs on push/PR to `main`: format check, analyze, Flutter tests + coverage, PHPUnit
- **ios.yml** — manual unsigned IPA build
- **android-release.yml** — manual or tag (`v*`) APK + AAB artifacts

## Secrets & config

Never commit: `backend/config.php`, keystore files, API secrets, `.claude/settings.local.json`

TMDB and JWT secrets live only on the server / local config.

## When refactoring large screens

1. Extract presentational widgets first (no behavior change)
2. Keep orchestrator responsible for providers, navigation, and side effects
3. Add at least one widget smoke test for the screen area
4. Run analyze + tests

## Docs

- `CONTRIBUTING.md` — setup and style for humans
- `docs/YOL_HARITASI_test_ve_repo.md` — test & repo hygiene roadmap (Turkish)
