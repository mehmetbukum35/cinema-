# Changelog

All notable changes to **cinema+** are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Complete accessibility semantics for search results, social cards/tabs, and movie detail rating controls
- `CHANGELOG.md` and expanded `README.md` (setup, tests, screenshots placeholder)
- Debug/profile warning when hitting production API without explicit `dart-define`
- EN trailer fallback caching under the primary locale key (avoids double TMDB fetch)

### Changed
- Search/social/detail touch targets now use `SpringButton` or Material ink where appropriate
- Minimum UI body font size bumped to 12px on search, social, detail, and profile surfaces
- `backend/src/Social.php` split into domain traits under `backend/src/Social/`

### Fixed
- Turkish hardcoded l10n fallbacks in search quick access and movie detail review toggles
- CI integration tests and sync test schema alignment (Phase 1–2)

## [2026-07] — Phase 1–3 polish

### Added
- Sign in with Apple, TMDB logo attribution, live app version display
- iOS TestFlight CI signing pipeline
- Widget smoke tests for profile, browse, social, movie detail, swipe, main shell
- Accessibility semantics pass (search input, filter chips, social actions, detail hero)

### Changed
- Refactored `search_screen` and `swipe_screen` into modular widget folders
- Recommendation engine boosts titles appearing in multiple seed similar lists
- API timeout handling and sync error visibility improvements

### Fixed
- Narrow-screen overflows in social, swipe, and detail screens
- Auth JSON parsing hardening and login integration test selectors
- Missing English l10n keys and CI integration test drift after profile refactor
- Backend FCM IPv4 curl and iOS orientation / encryption compliance

## [Earlier]

- Initial Flutter + PHP monorepo: swipe discovery, delta sync, social feed, match modes
- TMDB proxy via backend (`GET /tmdb/*`); client no longer needs TMDB API key
- Turkish (default) and English localization

[Unreleased]: https://github.com/mehmetbukum35/cinema-/compare/main...HEAD
