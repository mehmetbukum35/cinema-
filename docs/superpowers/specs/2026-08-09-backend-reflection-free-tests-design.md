# Reflection-Free Backend Tests Design

## Goal

Remove reflection-based access to private implementation details from
`SocialWebRendererTopListTest`, `ModerationAnalyticsPanelTest`, and
`TasteDnaWebTextTest` while preserving current public behavior and test coverage.

This is the first of four independent hardening projects. Logger/sink cleanup,
sync-auth-database invariant consolidation, and session/sync boundary changes are
explicitly out of scope for this design.

## Architecture

### Social web profile catalog

Create `backend/src/SocialWebProfileCatalog.php` as a focused query collaborator.
It receives a `PDO` in its constructor and exposes:

```php
public function loadTopList(int $userId, bool $isTv, string $lang): array
```

The method owns the existing Top 20 query, locale fallback, media filtering,
ordering, rank assignment, and metadata projection. `SocialWebRenderer` accepts
an optional `SocialWebProfileCatalog` as its second constructor argument and
creates one from its existing `PDO` when the argument is null. It uses the public
catalog method for movie and TV shelves while retaining orchestration, template
rendering, and its existing error/log boundary. Existing one-argument construction
remains compatible.

PDO exceptions are not swallowed by the catalog. They propagate to the existing
`SocialWebRenderer` catch path so runtime error behavior remains unchanged.

### Moderation panel renderer

Create `backend/src/ModerationPanelRenderer.php` as a pure HTML collaborator. It
exposes this public contract:

```php
public function render(
    string $csrf,
    string $actionUrl,
    array $open,
    array $hidden,
    array $banned,
    ?array $recommendations,
): string
```

The arrays retain the shapes currently accepted by `Moderation::html()`. Passing
the action URL explicitly keeps panel routing and global request state outside the
renderer.

`Moderation` retains session management, authorization, CSRF validation,
redirects, database access, warning logs, and response emission. After gathering
data, `Moderation::renderPanel()` passes it to `ModerationPanelRenderer` and emits
the returned HTML. The renderer does not access globals, headers, sessions, PDO,
or logging.

The current visible strings and HTML sections remain unchanged. A null analytics
report continues to render the existing migration guidance.

### Existing public boundaries

`Social::webRenderer()` is already public. Its test calls it directly and asserts
that it returns `SocialWebRenderer`; no new API is required.

`TasteDnaWebText::getThemesTr()` remains private. Tests verify dictionary loading
through `TasteDnaWebText::build()`, using a known Turkish theme and an unknown
theme. Asset and backend fallback JSON equality remains a separate filesystem
contract.

## Data Flow

### Public profile

1. `SocialWebRenderer` loads the public user and profile inputs.
2. It calls `SocialWebProfileCatalog::loadTopList($userId, false, $lang)` for movies.
3. It calls `SocialWebProfileCatalog::loadTopList($userId, true, $lang)` for TV.
4. It passes the ordered results to the existing profile template.
5. Database failures propagate to the current renderer-level logging and error page.

### Moderation panel

1. `Moderation` authenticates the request and loads panel data.
2. Recommendation-query failure retains the current warning log and produces a
   null analytics report.
3. `ModerationPanelRenderer::render()` converts the prepared data to HTML through
   the exact public contract defined above.
4. `Moderation` emits the returned HTML.

### Taste DNA theme mapping

1. The test confirms the shared asset JSON and backend fallback JSON are valid and
   identical.
2. It passes a known key to `TasteDnaWebText::build()`.
3. It verifies the translated public output, proving that the private loader feeds
   observable behavior.
4. It verifies that an unknown key remains hidden on the Turkish public profile.

## Testing Strategy

All production changes follow red-green-refactor. Each collaborator is introduced
only after a failing behavior test establishes its public contract.

### SocialWebProfileCatalog coverage

- Movie and TV lists are isolated.
- Results preserve the user's order and receive one-based ranks.
- Each media list is capped at 20 entries.
- Deleted rows and another user's rows are excluded.
- Missing requested-locale metadata falls back to `und`.
- Poster and backdrop metadata are projected unchanged.

### ModerationPanelRenderer coverage

- A present analytics report renders the period, model version, action counts,
  percentage, and existing moderation sections.
- A null analytics report renders the current unavailable/migration guidance.
- Tests call only the public renderer contract.

### TasteDnaWebText coverage

- Asset and fallback dictionaries remain valid and identical.
- A known theme is translated through `build()`.
- An unknown theme is hidden through `build()`.
- No private dictionary loader is invoked directly.

### Social delegation coverage

- `Social::webRenderer()` is called directly.
- It returns a `SocialWebRenderer` instance.

## Completion Criteria

- The three target test files contain no `ReflectionClass`, `ReflectionMethod`,
  `getMethod()`, or `setAccessible()` use.
- Public HTML, localization, Top 20 ordering, and fallback behavior are unchanged.
- Targeted PHPUnit tests pass.
- The complete PHPUnit suite passes.
- PHPStan passes at the repository's configured level.
- Each independently testable transformation receives code review before the next
  transformation proceeds.
- Changes use focused Conventional Commits with no unrelated refactoring.
- After every source commit, run `graphify . --update --code-only`, followed by
  `graphify cluster-only .`, so the project graph matches the committed code.

## Explicit Non-Goals

- Do not introduce logger/sink infrastructure in this project.
- Do not reorganize sync, authentication, or database ownership.
- Do not change public copy, profile layout, moderation authorization, or API routes.
- Do not make existing private methods public merely to satisfy tests.
