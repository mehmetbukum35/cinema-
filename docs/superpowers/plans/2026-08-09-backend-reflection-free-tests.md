# Reflection-Free Backend Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace reflection-based backend tests with public, behavior-oriented contracts without changing user-visible profile or moderation behavior.

**Architecture:** Extract the Top 20 query into `SocialWebProfileCatalog` and moderation HTML generation into `ModerationPanelRenderer`. Keep orchestration, PDO error boundaries, sessions, redirects, and response emission in the existing classes; verify Taste DNA mapping and Social renderer construction through their existing public APIs.

**Tech Stack:** PHP 8.2+, PDO/SQLite, PHPUnit 11, PHPStan 2.1, Composer classmap autoloading.

## Global Constraints

- Follow `docs/superpowers/specs/2026-08-09-backend-reflection-free-tests-design.md` exactly.
- Do not change public copy, profile layout, moderation authorization, API routes, or error logging behavior.
- Do not make existing private methods public solely for tests.
- Keep PHP array shapes documented for PHPStan level 6.
- Use real in-memory SQLite behavior; do not replace PDO with mocks.
- Run a focused code review after every task and resolve Critical/Important findings before proceeding.
- Use Conventional Commits and exclude the untracked `graphify-out/` directory from Git staging.
- After each source commit, run `graphify . --update --code-only` and `graphify cluster-only .`.

---

## File Structure

- Create `backend/src/SocialWebProfileCatalog.php`: public Top 20 query boundary.
- Modify `backend/src/SocialWebRenderer.php`: delegate Top 20 loading to the catalog.
- Modify `backend/tests/SocialWebRendererTopListTest.php`: test the catalog and public `Social::webRenderer()` without reflection.
- Modify `backend/tests/TasteDnaWebTextTest.php`: verify dictionary behavior only through `build()`.
- Create `backend/src/ModerationPanelRenderer.php`: pure moderation HTML renderer.
- Modify `backend/src/Moderation.php`: collect request/DB data and delegate HTML generation.
- Modify `backend/tests/ModerationAnalyticsPanelTest.php`: call the public renderer without reflection.

---

### Task 1: Extract the public social profile catalog

**Files:**
- Create: `backend/src/SocialWebProfileCatalog.php`
- Modify: `backend/src/SocialWebRenderer.php:1-10,48-53,261-286`
- Modify: `backend/tests/SocialWebRendererTopListTest.php:1-55`

**Interfaces:**
- Consumes: `PDO` configured with `PDO::FETCH_ASSOC` by the caller/test.
- Produces: `SocialWebProfileCatalog::__construct(PDO $db)` and `SocialWebProfileCatalog::loadTopList(int $userId, bool $isTv, string $lang): array`.
- Preserves: `SocialWebRenderer::__construct(PDO $db, ?SocialWebProfileCatalog $catalog = null)` and existing one-argument callers.

- [ ] **Step 1: Replace the reflective catalog test with a failing public-contract test**

Add the new class requirement and instantiate the wished-for public API. Keep the existing SQLite schema/fixture, then extend it with 22 movie rows so the 20-row cap is observable rather than inferred.

```php
require_once __DIR__ . '/../src/SocialWebProfileCatalog.php';

public function testCatalogLoadsSeparatedTopTwentyInUserOrderWithLocaleFallback(): void
{
    $db = new PDO('sqlite::memory:');
    $db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $db->exec('CREATE TABLE favorites (user_id INTEGER, id INTEGER, is_tv INTEGER, created_at INTEGER, deleted INTEGER DEFAULT 0)');
    $db->exec('CREATE TABLE titles (tmdb_id INTEGER, is_tv INTEGER, locale TEXT, title TEXT, poster_path TEXT, backdrop_path TEXT, vote_average REAL, release_date TEXT)');
    $db->exec("INSERT INTO favorites VALUES
        (7, 101, 0, 2, 0), (7, 102, 0, 0, 0), (7, 103, 0, 1, 0),
        (7, 201, 1, 0, 0), (7, 999, 0, 3, 1), (8, 888, 0, 0, 0)");
    $db->exec("INSERT INTO titles VALUES
        (101, 0, 'tr', 'Üçüncü Film', '/3.jpg', '/3b.jpg', 8.1, '2003-01-01'),
        (102, 0, 'tr', 'Birinci Film', '/1.jpg', '/1b.jpg', 8.9, '2001-01-01'),
        (103, 0, 'und', 'Fallback Film', '/2.jpg', NULL, 8.4, '2002-01-01'),
        (201, 1, 'tr', 'Birinci Dizi', '/tv.jpg', '/tvb.jpg', 9.0, '2020-01-01')");

    for ($id = 300; $id < 322; $id++) {
        $db->prepare('INSERT INTO favorites VALUES (7, ?, 0, ?, 0)')->execute([$id, $id]);
        $db->prepare("INSERT INTO titles VALUES (?, 0, 'tr', ?, NULL, NULL, 0, NULL)")
            ->execute([$id, 'Film ' . $id]);
    }

    $catalog = new SocialWebProfileCatalog($db);
    $movies = $catalog->loadTopList(7, false, 'tr');
    $shows = $catalog->loadTopList(7, true, 'tr');

    self::assertCount(20, $movies);
    self::assertSame([102, 103, 101], array_map('intval', array_column(array_slice($movies, 0, 3), 'movie_id')));
    self::assertSame(range(1, 20), array_column($movies, 'rank'));
    self::assertSame('Fallback Film', $movies[1]['title']);
    self::assertSame('/1b.jpg', $movies[0]['backdrop_path']);
    self::assertSame([201], array_map('intval', array_column($shows, 'movie_id')));
}
```

- [ ] **Step 2: Run the focused test and verify the intended RED state**

Run:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter SocialWebRendererTopListTest
```

Expected: ERROR because `backend/src/SocialWebProfileCatalog.php` or class `SocialWebProfileCatalog` does not exist. The failure must occur before any assertion; syntax or fixture errors must be corrected before continuing.

- [ ] **Step 3: Implement the minimal catalog**

Create `backend/src/SocialWebProfileCatalog.php` with the existing query moved verbatim from `SocialWebRenderer::loadTopList()`:

```php
<?php
declare(strict_types=1);

final class SocialWebProfileCatalog
{
    public function __construct(private PDO $db) {}

    /** @return list<array<string, mixed>> */
    public function loadTopList(int $userId, bool $isTv, string $lang): array
    {
        $st = $this->db->prepare(
            'SELECT f.id AS movie_id, f.is_tv,
                    COALESCE(t.title, tf.title) AS title,
                    COALESCE(t.poster_path, tf.poster_path) AS poster_path,
                    COALESCE(t.backdrop_path, tf.backdrop_path) AS backdrop_path,
                    COALESCE(t.vote_average, tf.vote_average) AS vote_average,
                    COALESCE(t.release_date, tf.release_date) AS release_date
             FROM favorites f
             LEFT JOIN titles t ON t.tmdb_id = f.id AND t.is_tv = f.is_tv AND t.locale = ?
             LEFT JOIN titles tf ON tf.tmdb_id = f.id AND tf.is_tv = f.is_tv AND tf.locale = \'und\'
             WHERE f.user_id = ? AND f.is_tv = ? AND f.deleted = 0
             ORDER BY f.created_at ASC, f.id ASC
             LIMIT 20'
        );
        $st->execute([$lang, $userId, $isTv ? 1 : 0]);
        $rows = $st->fetchAll();
        foreach ($rows as $index => &$row) {
            $row['rank'] = $index + 1;
        }
        unset($row);
        return $rows;
    }
}
```

- [ ] **Step 4: Delegate from `SocialWebRenderer` and delete its private duplicate**

Require the class, add a catalog property, preserve the old constructor call shape, replace both calls, and remove the old private method:

```php
require_once __DIR__ . '/SocialWebProfileCatalog.php';

private SocialWebProfileCatalog $catalog;

public function __construct(private PDO $db, ?SocialWebProfileCatalog $catalog = null)
{
    $this->catalog = $catalog ?? new SocialWebProfileCatalog($db);
}
```

```php
$topMovies = $this->catalog->loadTopList($userId, false, $lang);
$topShows = $this->catalog->loadTopList($userId, true, $lang);
```

- [ ] **Step 5: Remove reflection from the Social construction test**

Replace the reflective method lookup with the existing public API:

```php
$renderer = $social->webRenderer();
self::assertInstanceOf(SocialWebRenderer::class, $renderer);
self::assertSame($renderer, $social->webRenderer());
```

The identity assertion protects the lazy singleton behavior that consumers rely on.

- [ ] **Step 6: Verify GREEN and static analysis**

Run:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter SocialWebRendererTopListTest
composer phpstan
```

Expected: the focused tests pass with zero errors; PHPStan exits 0. If PHPStan reports `fetchAll()` as mixed, add a local `/** @var list<array<string, mixed>> $rows */` annotation immediately above `$rows = $st->fetchAll();` rather than weakening the return type.

- [ ] **Step 7: Commit, review, and refresh graphify**

```powershell
git add backend/src/SocialWebProfileCatalog.php backend/src/SocialWebRenderer.php backend/tests/SocialWebRendererTopListTest.php
git commit -m "refactor(profile): expose top list query boundary"
$py = Get-Content -Raw graphify-out\.graphify_python
& $py -m graphify . --update --code-only
& $py -m graphify cluster-only .
```

Request code review for the commit range. Resolve Critical/Important findings in a focused follow-up commit before Task 2.

---

### Task 2: Test Taste DNA dictionary behavior through `build()`

**Files:**
- Modify: `backend/tests/TasteDnaWebTextTest.php:179-206`

**Interfaces:**
- Consumes: `TasteDnaWebText::build(?array $dna, string $lang = 'tr'): ?array`.
- Produces: no new production interface; removes direct access to `getThemesTr()`.

- [ ] **Step 1: Record the existing characterization behavior**

Run the focused test before editing:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter TasteDnaWebTextTest
```

Expected: PASS. This task changes test structure, not production behavior, so the existing public tests are the characterization baseline.

- [ ] **Step 2: Replace the private-loader assertion with public output assertions**

Keep both JSON validity/equality assertions. Delete `ReflectionClass`, `getMethod()`, `setAccessible()`, and `$loadedMap`. Add this public behavior check inside `testLexiconParityWithDart()`:

```php
$view = TasteDnaWebText::build([
    'archetype' => 'genre_nomad',
    'total_rated' => 20,
    'themes' => ['revenge', 'not_in_dictionary'],
], 'tr');

self::assertNotNull($view);
self::assertSame(['İntikam'], $view['themes']);
```

This proves the shared dictionary is consumed by observable output and unknown raw keys remain hidden.

- [ ] **Step 3: Verify the focused test and mutation sensitivity**

Run:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter TasteDnaWebTextTest
```

Expected: PASS. Then temporarily change the local test fixture key from `revenge` to `not_in_dictionary`, rerun the single method, and confirm it fails because `['İntikam']` is absent; restore the fixture immediately and rerun to PASS. Do not modify either production JSON file for the mutation check.

- [ ] **Step 4: Commit, review, and refresh graphify**

```powershell
git add backend/tests/TasteDnaWebTextTest.php
git commit -m "test(dna): verify theme lexicon through public output"
$py = Get-Content -Raw graphify-out\.graphify_python
& $py -m graphify . --update --code-only
& $py -m graphify cluster-only .
```

Request code review for the commit range. Resolve Critical/Important findings before Task 3.

---

### Task 3: Extract the pure moderation panel renderer

**Files:**
- Create: `backend/src/ModerationPanelRenderer.php`
- Modify: `backend/src/Moderation.php:1-18,102-176,235-end`
- Modify: `backend/tests/ModerationAnalyticsPanelTest.php:1-58`

**Interfaces:**
- Consumes: CSRF token, absolute action URL, open/hidden/banned row lists, and nullable recommendation report.
- Produces: `ModerationPanelRenderer::render(string $csrf, string $actionUrl, array $open, array $hidden, array $banned, ?array $recommendations): string`.
- Preserves: `Moderation::__construct(PDO $db, string $adminKey, ?RecommendationAnalytics $recommendationAnalytics = null)` and all public routes.

- [ ] **Step 1: Rewrite analytics tests against the wished-for public renderer**

At the top of the test require the new class. Replace each `ReflectionMethod` setup with direct calls:

```php
require_once __DIR__ . '/../src/ModerationPanelRenderer.php';

$renderer = new ModerationPanelRenderer();
$html = $renderer->render('csrf', '/admin/moderation/action', [], [], [], [
    'period_days' => 30,
    'groups' => [[
        'model_version' => 'recommendation_v4_ab_control',
        'surface' => 'browse',
        'shown' => 10,
        'detail_opened' => 4,
        'trailer_opened' => 2,
        'watchlisted' => 1,
        'rated' => 2,
        'dismissed' => 3,
        'positive_rate' => 0.3,
    ]],
]);
```

For the unavailable case call:

```php
$html = (new ModerationPanelRenderer())->render(
    'csrf',
    '/admin/moderation/action',
    [],
    [],
    [],
    null,
);
```

Keep every existing HTML assertion unchanged.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter ModerationAnalyticsPanelTest
```

Expected: ERROR because `ModerationPanelRenderer.php` or class `ModerationPanelRenderer` does not exist.

- [ ] **Step 3: Create the pure renderer by moving existing HTML code unchanged**

Create the class and move the complete bodies of current `Moderation::html()` and `Moderation::recommendationHtml()` into it without rewriting their HTML assembly. Rename `html()` to public `render()`, add `$actionUrl` as the second parameter, remove `$this->panelPath()`, and escape the supplied URL once. Apply these exact signature and initialization transformations before relocating the unchanged closures and return expressions:

```diff
- private function html(
-     string $key,
+ public function render(
+     string $csrf,
+     string $actionUrl,
      array $open,
      array $hidden,
      array $banned,
      ?array $recommendations,
  ): string
  {
-     $e = fn($v) => htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
-     $keyH = $e($key);
-     $actionUrl = $e($this->panelPath() . '/action');
+     $e = static fn(mixed $value): string =>
+         htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
+     $keyH = $e($csrf);
+     $actionUrlH = $e($actionUrl);
```

Relocate every remaining statement from `Moderation::html()` after those three initialization lines into `ModerationPanelRenderer::render()`. Rename the closure capture/use sites of `$actionUrl` to `$actionUrlH`. Relocate `Moderation::recommendationHtml()` with its signature and body unchanged. The completed file must contain the full original HTML, CSS, card closures, metrics calculation, and recommendation table logic.

- [ ] **Step 4: Delegate from `Moderation::renderPanel()` and delete private render methods**

Add the class requirement at the top:

```php
require_once __DIR__ . '/ModerationPanelRenderer.php';
```

Replace the existing echo call with:

```php
$renderer = new ModerationPanelRenderer();
echo $renderer->render(
    $key,
    $this->panelPath() . '/action',
    $open,
    $hidden,
    $banned,
    $recommendations,
);
```

Delete `Moderation::html()` and `Moderation::recommendationHtml()` only after their full bodies exist in the collaborator. Do not move `panelPath()`, session logic, headers, database queries, logging, or `exit`.

- [ ] **Step 5: Verify GREEN, the full backend suite, and PHPStan**

Run:

```powershell
cd backend
vendor\bin\phpunit --configuration phpunit.xml --filter ModerationAnalyticsPanelTest
composer test
composer phpstan
```

Expected: focused tests and the complete PHPUnit suite pass; PHPStan exits 0. Compare the two focused HTML assertions with their pre-refactor values to confirm copy and percentage formatting are unchanged.

- [ ] **Step 6: Commit, review, and refresh graphify**

```powershell
git add backend/src/ModerationPanelRenderer.php backend/src/Moderation.php backend/tests/ModerationAnalyticsPanelTest.php
git commit -m "refactor(moderation): extract panel renderer"
$py = Get-Content -Raw graphify-out\.graphify_python
& $py -m graphify . --update --code-only
& $py -m graphify cluster-only .
```

Request code review for the commit range. Resolve Critical/Important findings before Task 4.

---

### Task 4: Enforce the reflection-free boundary and finish verification

**Files:**
- Verify: `backend/tests/SocialWebRendererTopListTest.php`
- Verify: `backend/tests/TasteDnaWebTextTest.php`
- Verify: `backend/tests/ModerationAnalyticsPanelTest.php`

**Interfaces:**
- Consumes: the public contracts introduced in Tasks 1-3.
- Produces: no code; supplies final evidence that the design and test boundary are complete.

- [ ] **Step 1: Prove reflection is absent from the three scoped groups**

Run:

```powershell
$files = @(
  'backend/tests/SocialWebRendererTopListTest.php',
  'backend/tests/TasteDnaWebTextTest.php',
  'backend/tests/ModerationAnalyticsPanelTest.php'
)
$hits = Select-String -LiteralPath $files -Pattern 'ReflectionClass|ReflectionMethod|getMethod\(|setAccessible\('
if ($hits) { $hits; throw 'Reflection remains in scoped tests' }
```

Expected: no output and exit 0.

- [ ] **Step 2: Run all required verification commands**

```powershell
cd backend
composer test
composer phpstan
```

Expected: all PHPUnit tests pass with zero failures/errors and PHPStan exits 0 at the configured level.

- [ ] **Step 3: Inspect scope and request final code review**

```powershell
cd ..
git status --short
git diff --check HEAD~3..HEAD
git diff --stat HEAD~3..HEAD
```

Confirm only the planned backend source/tests and the approved docs commits are present. Dispatch a final reviewer with the design spec, this plan, base SHA before Task 1, and current HEAD. Resolve every Critical/Important finding with a focused tested commit; record Minor findings without expanding scope.

- [ ] **Step 4: Refresh graphify after any review-fix commit**

If review produced a source fix commit, run:

```powershell
$py = Get-Content -Raw graphify-out\.graphify_python
& $py -m graphify . --update --code-only
& $py -m graphify cluster-only .
```

If review produced no source change, verify that `graphify-out/graph.json`, `GRAPH_REPORT.md`, and `graph.html` are newer than the last source commit and do not rebuild again.
