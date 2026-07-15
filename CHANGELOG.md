# Changelog

All notable changes to **cinema+** are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Release-only Firebase Crashlytics reporting for uncaught Flutter, platform, and asynchronous errors; API 5xx reports are correlated with structured backend JSON logs through redacted `X-Request-ID` metadata
- Central backend observability: structured JSON logs, global exception capture, configurable log sink, request IDs on responses, and recursive credential/token redaction
- **Pick Together (live couch mode)**: two friends swipe the same deck on their own phones; the first mutual like wins. Deck is built from the shared watchlist intersection plus the recommendation engine's picks; realtime via short polling (shared-hosting friendly), FCM pushes for invite and match, one-active-session rule, and the opponent's individual votes are never exposed (only progress). New `/social/couch/*` endpoints, `couch_sessions` table (migration 014), Together-tab LIVE card with pending-invite badge, full session screen (friend picker → voting → match celebration / no-match retry)
- DNA milestone moments in the swipe loop: a one-time invite sheet at the 5th/25th/50th rating surfaces Cinema DNA inside the core loop (its only entry point was a Profile-tab banner) and shows the measured recommendation hit rate for the first time
- Release-reminder disclosure: adding an unreleased title to the watchlist now tells the user "we'll remind you on release day" (the reminder was already scheduled silently)
- End-to-end auth+sync flow test (`test/auth_sync_flow_test.dart`): real ApiService/SyncService/SQLite against a stateful fake backend — covers push/pull, second-device pull, last-write-wins both ways, silent token refresh with rotation, session expiry keeping local data, and idempotent re-push after re-login
- Machine-readable `code` field on backend error responses; client maps errors by code first and falls back to legacy Turkish message matching for old servers
- `GET /social/match/taste-all`: all friends' taste-match scores in a single request (client falls back to per-friend calls on old servers)
- Complete accessibility semantics for search results, social cards/tabs, and movie detail rating controls
- `CHANGELOG.md` and expanded `README.md` (setup, tests, screenshots placeholder)
- Debug/profile warning when hitting production API without explicit `dart-define`
- EN trailer fallback caching under the primary locale key (avoids double TMDB fetch)

### Changed
- Split the monolithic `ApiService` into a 235-line shared `ApiClient` plus focused auth, sync, social, recommendation, and live-couch API modules while preserving the existing facade and provider contracts
- Watchlist and stats screens now render local data immediately and refresh after background sync (offline-first, no more sync-blocked spinner)
- All `ApiService` error paths decode responses defensively (HTML error pages no longer surface as `FormatException`)
- `/me` response now includes `apple_sub`; verification/reset e-mails rebranded from "Ne İzlesem" to "Cinema+"
- `movie_detail_sheet.dart` split (1,235 → 653 lines): presentational sections extracted to `movie_detail/` (sheet shell, rating section, comment editor, friends reviews, text sections, shared block/recommend/delete-confirm actions); public `MovieDetailSheet` statics kept as thin delegates
- Search/social/detail touch targets now use `SpringButton` or Material ink where appropriate
- Minimum UI body font size bumped to 12px on search, social, detail, and profile surfaces
- `backend/src/Social.php` split into domain traits under `backend/src/Social/`

### Fixed
- Taste DNA was regenerated and re-published to the server on every sync: recommendation-cache invalidation no longer wipes the DNA cache or the last-published hash (DNA cache self-validates via its input hash)
- `GET /social/friends` no longer exposes user e-mail addresses (username → e-mail harvesting via pending requests)
- Removed dead code: `PrefsService.getMovieRating`, `RecommendationEngine.invalidateTasteVector`, no-op `forceEnforce` parameter in `TmdbService`
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
