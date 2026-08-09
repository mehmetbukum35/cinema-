# Task 6 Report: `PrefsLibraryFacade` — DB delege katmanı

## Status: DONE

## Summary

Created `lib/services/prefs/library_facade.dart` with `class PrefsLibraryFacade`, moved verbatim from `prefs_service.dart`:

- Favorites: `getFavoriteMovies`, `getFavoriteTvShows`, `saveFavoriteMovies`, `saveFavoriteTvShows`, `mergeFavoriteMovies`, `mergeFavoriteTvShows`, `_mergeFavorites`, `favoritesCap`, `favoriteRankWeight`.
- Ratings: `saveRating` (with its full side-effect chain intact), `getRating`, `deleteComment`, `getCommentedRatings`, `getRatedIds`, `deleteRating`, `getRatingCount`, `getStats`.
- Watchlist: `addToWatchlist`, `removeFromWatchlist`, `isInWatchlist`, `getWatchlist`.
- Search history: `addSearchHistory`, `getSearchHistory`, `clearSearchHistory`.
- Seasons: `toggleSeason`, `getWatchedSeasons`.

`prefs_service.dart` now only forwards to `PrefsLibraryFacade` for all of the above (one-line delegates), preserving every public signature and doc comment.

### `favoriteGenreBase` de-duplication (the Task 5 flagged concern)

- Task 5 had temporarily duplicated `favoritesCap`/`favoriteRankWeight`/`favoriteGenreBase` as private members inside `PrefsTastePrefs` because it couldn't import `prefs_service.dart` (cycle rule) and the real definitions lived there at the time.
- Now that `PrefsLibraryFacade.favoritesCap` / `.favoriteRankWeight` / `.favoriteGenreBase` are the single source (the latter made public, not `_favoriteGenreBase`, specifically so `taste_prefs.dart` can reference it), `taste_prefs.dart` imports `prefs/library_facade.dart` and calls `PrefsLibraryFacade.favoriteGenreBase * PrefsLibraryFacade.favoriteRankWeight(rank)` in `_calculateGenreWeights`. Its private `_favoritesCap`/`_favoriteGenreBase`/`_favoriteRankWeight` copies are deleted.
- `favoritesCap` in `PrefsService` becomes a const-forward: `static const favoritesCap = PrefsLibraryFacade.favoritesCap;` (per brief's const-forward pattern, matching how `dnaMilestones` was already forwarded in Task 5).

### Cycle-rule handling

- `library_facade.dart` imports `taste_prefs.dart` (to call `PrefsTastePrefs.invalidateGenreWeights()` from `saveFavoriteMovies`/`saveFavoriteTvShows`/`_mergeFavorites`/`saveRating`/`deleteRating`, and `PrefsTastePrefs.getLikedGenreIds()` from `getStats`'s genre fallback).
- `taste_prefs.dart` imports `library_facade.dart` (for the rank-weight formula, described above).
- This is a two-file import cycle **between the two `prefs/` domain modules**, not a cycle back to `prefs_service.dart` — neither file imports `prefs_service.dart`. Dart natively supports circular library imports (no textual-inclusion model like C headers), so this compiles and analyzes cleanly; confirmed with a clean `flutter analyze` run. Documented this explicitly in `taste_prefs.dart`'s class doc comment so it isn't mistaken for an accidental cycle later.

## Commits

- `8edc1ad` — `refactor(prefs): extract PrefsLibraryFacade over DatabaseHelper delegates` (touches `lib/services/prefs/library_facade.dart` (new), `lib/services/prefs/taste_prefs.dart`, `lib/services/prefs_service.dart`).

## Test summary

- `flutter test test/prefs_service_test.dart test/watchlist_provider_test.dart test/top_list_provider_test.dart` → 36 tests, all passed.
- `flutter test` (full suite) → 575 tests, all passed.
- `dart format --set-exit-if-changed lib/services/prefs lib/services/prefs_service.dart` → clean.
- `flutter analyze` (full project) → No issues found.

## Concerns

- None outstanding for this task. `favoriteGenreBase` had to be made public (no leading underscore) in `PrefsLibraryFacade`, deviating slightly from the brief's illustrative skeleton (which showed it as `_favoriteGenreBase`) — a Dart library-private (`_`-prefixed) member is invisible outside its own file, so `taste_prefs.dart` could not have referenced a private copy in `library_facade.dart`. Making it public was necessary to satisfy "shared const" per the brief's own wording.
- The `library_facade.dart` ↔ `taste_prefs.dart` mutual import is intentional and verified safe (see Cycle-rule handling above), but future refactors in either file should keep in mind neither may import `prefs_service.dart`.

## Important review finding fix

- This follow-up supersedes the earlier cycle-rule handling and related concern above.
- Added dependency-free `lib/services/prefs/favorite_weights.dart` as the single source for `favoritesCap`, public `favoriteGenreBase`, and `favoriteRankWeight(int rank)`.
- `PrefsLibraryFacade` forwards its existing public members to the leaf, preserving `PrefsService.favoritesCap` and `PrefsService.favoriteRankWeight`.
- `PrefsTastePrefs` now imports the leaf directly. `rg -n "^import " lib/services/prefs/favorite_weights.dart lib/services/prefs/library_facade.dart lib/services/prefs/taste_prefs.dart` shows `library_facade.dart` and `taste_prefs.dart` both importing `favorite_weights.dart`, with no `taste_prefs.dart` → `library_facade.dart` or `prefs/*` → `prefs_service.dart` import.

### Fix verification

- `flutter test test/prefs_service_test.dart test/watchlist_provider_test.dart test/top_list_provider_test.dart test/recommendation_engine_test.dart test/similarity_test.dart` → 75 tests, all passed.
- `dart format lib/services/prefs lib/services/prefs_service.dart` → formatted 7 files, 0 changed.
- `flutter analyze lib/services/prefs lib/services/prefs_service.dart` → No issues found.
