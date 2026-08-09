# Baseline Migration Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace heuristic migration-history detection with a checksum-protected `029` baseline and safe `030+` MariaDB migrations.

**Architecture:** Keep `backend/migrate.php` as a thin CLI adapter. Put deterministic filename/checksum discovery in `MigrationCatalog`, MariaDB `029` marker checks in `BaselineSchemaValidator`, and locking, ledger, bootstrap, adoption, status, and forward execution in `MigrationManager`. Exercise deterministic rules with PHPUnit and MariaDB behavior with an opt-in integration test that CI runs against MariaDB 10.6.

**Tech Stack:** PHP 8.2–8.4, PDO MySQL, MariaDB 10.6, PHPUnit 11, GitHub Actions, SHA-256.

## Global Constraints

- `backend/migrations/database.sql` is the authoritative baseline through version `029`.
- New incremental migration filenames start at `030_*.sql`.
- Keep `backend/migrate.php` as the only CLI entry point.
- Store `version`, lowercase SHA-256 `checksum`, and millisecond `applied_at` in `schema_migrations`.
- Do not add a request-time schema-version gate.
- Do not modify `.cpanel.yml` or automatically migrate during deployment.
- Never log passwords, full DSNs, configuration secrets, or complete SQL bodies.
- MariaDB DDL is not described or treated as transactionally reversible.
- Preserve the user's unrelated `.gitignore` modification.

## File Structure

- Create `backend/src/Migrations/MigrationFile.php`: immutable migration descriptor.
- Create `backend/src/Migrations/MigrationCatalog.php`: baseline checksum and strict `030+` discovery.
- Create `backend/src/Migrations/BaselineSchemaValidator.php`: exact MariaDB schema-marker validation for `027–029`.
- Create `backend/src/Migrations/MigrationManager.php`: advisory lock, ledger, bootstrap, adoption, status, and pending execution.
- Replace internals of `backend/migrate.php`: CLI parsing, configuration loading, manager invocation, sanitized output.
- Modify `backend/migrations/database.sql`: correct the baseline-version header comment to `029` without changing SQL.
- Create `backend/tests/MigrationCatalogTest.php`: deterministic catalog unit tests.
- Create `backend/tests/MigrationManagerMariaDbTest.php`: opt-in real-MariaDB integration tests.
- Modify `.github/workflows/ci.yml`: MariaDB 10.6 service and migration integration-test environment.
- Modify `backend/README.md` and `backend/API_VE_SEMA.md`: baseline/adoption/status operator instructions.

---

### Task 1: Strict Migration Catalog

**Files:**
- Create: `backend/src/Migrations/MigrationFile.php`
- Create: `backend/src/Migrations/MigrationCatalog.php`
- Create: `backend/tests/MigrationCatalogTest.php`

**Interfaces:**
- Produces: `MigrationFile::__construct(int $version, string $name, string $path, string $checksum)`.
- Produces: `MigrationCatalog::__construct(string $migrationsDir, int $baselineVersion = 29)`.
- Produces: `MigrationCatalog::baseline(): MigrationFile` with name `029_baseline` and path `database.sql`.
- Produces: `MigrationCatalog::pendingCandidates(): array<int, MigrationFile>` sorted by numeric version.
- Later tasks consume all four interfaces without renaming them.

- [ ] **Step 1: Write failing catalog tests**

Create a temporary directory per test, copy a minimal `database.sql`, and use `file_put_contents()` only inside the PHPUnit temporary directory. Cover the exact rules below:

```php
public function testBuildsBaselineAndSortsForwardMigrations(): void
{
    $dir = $this->migrationDir([
        'database.sql' => 'CREATE TABLE users (id INT);',
        '031_second.sql' => 'ALTER TABLE users ADD second_col INT;',
        '030_first.sql' => 'ALTER TABLE users ADD first_col INT;',
    ]);

    $catalog = new MigrationCatalog($dir);

    self::assertSame('029_baseline', $catalog->baseline()->name);
    self::assertSame(hash_file('sha256', "$dir/database.sql"), $catalog->baseline()->checksum);
    self::assertSame(
        ['030_first.sql', '031_second.sql'],
        array_map(static fn(MigrationFile $file): string => $file->name, $catalog->pendingCandidates()),
    );
}

/** @dataProvider invalidCatalogProvider */
public function testRejectsInvalidForwardCatalog(array $files, string $message): void
{
    $dir = $this->migrationDir(['database.sql' => 'SELECT 1;'] + $files);
    $this->expectException(RuntimeException::class);
    $this->expectExceptionMessage($message);
    (new MigrationCatalog($dir))->pendingCandidates();
}

public static function invalidCatalogProvider(): array
{
    return [
        'duplicate version' => [[
            '030_one.sql' => 'SELECT 1;',
            '030_two.sql' => 'SELECT 2;',
        ], 'Duplicate migration version 030'],
        'malformed sql' => [['001.sql' => 'SELECT 1;'], 'Invalid migration filename 001.sql'],
        'empty sql' => [['030_empty.sql' => '   '], 'Migration file is empty: 030_empty.sql'],
    ];
}

public function testIgnoresHistoricalNumberedFilesFoldedIntoBaseline(): void
{
    $dir = $this->migrationDir([
        'database.sql' => 'SELECT 1;',
        '029_titles_origin.sql' => 'ALTER TABLE titles ADD original_language VARCHAR(16);',
    ]);
    self::assertSame([], (new MigrationCatalog($dir))->pendingCandidates());
}
```

The fixture helper registers recursive cleanup with `tearDown()` and never writes under `backend/migrations`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```powershell
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationCatalogTest.php --no-coverage
```

Expected: failure because `MigrationCatalog` and `MigrationFile` do not exist.

- [ ] **Step 3: Implement the immutable descriptor and catalog**

`MigrationFile` contains four public readonly properties matching the constructor interface. `MigrationCatalog` must:

```php
private const FORWARD_PATTERN = '/^(\d{3})_[a-z0-9][a-z0-9_]*\.sql$/';

public function baseline(): MigrationFile
{
    $path = $this->migrationsDir . DIRECTORY_SEPARATOR . 'database.sql';
    return $this->describe($this->baselineVersion, '029_baseline', $path);
}

public function pendingCandidates(): array
{
    $files = glob($this->migrationsDir . DIRECTORY_SEPARATOR . '*.sql');
    if ($files === false) {
        throw new RuntimeException('Failed to scan migrations directory.');
    }

    $byVersion = [];
    foreach ($files as $path) {
        $name = basename($path);
        if ($name === 'database.sql') {
            continue;
        }
        if (!preg_match(self::FORWARD_PATTERN, $name, $matches)) {
            throw new RuntimeException("Invalid migration filename $name");
        }
        $version = (int) $matches[1];
        if ($version <= $this->baselineVersion) {
            continue; // Historical 002–029 files are folded into the baseline.
        }
        if (isset($byVersion[$version])) {
            throw new RuntimeException(sprintf('Duplicate migration version %03d', $version));
        }
        $byVersion[$version] = $this->describe($version, $name, $path);
    }
    ksort($byVersion, SORT_NUMERIC);
    return array_values($byVersion);
}
```

Historical `002–029` files are explicitly ignored. `describe()` rejects unreadable/empty content and uses `hash_file('sha256', $path)`.

- [ ] **Step 4: Run catalog tests and PHPStan**

Run:

```powershell
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationCatalogTest.php --no-coverage
composer --working-dir=backend phpstan
```

Expected: focused tests pass; PHPStan reports zero errors.

- [ ] **Step 5: Commit Task 1**

```powershell
git add backend/src/Migrations/MigrationFile.php backend/src/Migrations/MigrationCatalog.php backend/tests/MigrationCatalogTest.php
git commit -m "feat(database): add strict migration catalog"
```

---

### Task 2: Baseline Validation and Ledger Bootstrap

**Files:**
- Create: `backend/src/Migrations/BaselineSchemaValidator.php`
- Create: `backend/src/Migrations/MigrationManager.php`
- Create: `backend/tests/MigrationManagerMariaDbTest.php`

**Interfaces:**
- Consumes: `MigrationCatalog::baseline()` and `MigrationCatalog::pendingCandidates()`.
- Produces: `BaselineSchemaValidator::__construct(PDO $db, string $databaseName)`.
- Produces: `BaselineSchemaValidator::mismatches(): array<int, string>`.
- Produces: `MigrationManager::__construct(PDO $db, string $databaseName, MigrationCatalog $catalog, BaselineSchemaValidator $validator, ?callable $output = null)`.
- Produces: `MigrationManager::bootstrap(): void`, `adoptBaseline(): void`, `migrate(): int`, and `status(): array<string, mixed>`.
- Produces: `MigrationManager::run(): int`, which bootstraps an empty database when needed and then applies pending migrations.

- [ ] **Step 1: Write a MariaDB integration harness and failing bootstrap test**

The test skips unless all four environment variables exist: `MIGRATION_TEST_HOST`, `MIGRATION_TEST_USER`, `MIGRATION_TEST_PASSWORD`, and `MIGRATION_TEST_DATABASE_PREFIX`. In `setUp()`, connect without a database, validate the prefix against `/^[a-z0-9_]+$/`, create exact databases `${prefix}_subject` and `${prefix}_snapshot`, and connect to each with `PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION`. In `tearDown()`, drop only those two validated names.

Add:

```php
public function testBootstrapMatchesSnapshotAndRecordsChecksum(): void
{
    $manager = $this->manager($this->subject);
    $manager->bootstrap();
    $this->snapshot->exec((string) file_get_contents(self::MIGRATIONS . '/database.sql'));

    self::assertSame(
        $this->normalizedSchema($this->snapshotName),
        $this->normalizedSchema($this->subjectName),
    );
    self::assertSame(
        hash_file('sha256', self::MIGRATIONS . '/database.sql'),
        $this->subject->query(
            "SELECT checksum FROM schema_migrations WHERE version = '029_baseline'"
        )->fetchColumn(),
    );
}
```

`normalizedSchema()` reads `information_schema.tables`, `columns`,
`statistics`, and `table_constraints`, orders every row deterministically, and
JSON-encodes the result. It excludes only the `schema_migrations` table and
environment-generated `AUTO_INCREMENT` values; it retains engines, collations,
column definitions, index columns/order/uniqueness, and constraint types.

- [ ] **Step 2: Run the focused integration test and confirm RED**

Run against XAMPP MariaDB 10.4:

```powershell
$env:MIGRATION_TEST_HOST='127.0.0.1'
$env:MIGRATION_TEST_USER='root'
$env:MIGRATION_TEST_PASSWORD=''
$env:MIGRATION_TEST_DATABASE_PREFIX='cinema_migration_test'
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationManagerMariaDbTest.php --filter testBootstrapMatchesSnapshotAndRecordsChecksum --no-coverage
```

Expected: failure because `MigrationManager` does not exist.

- [ ] **Step 3: Implement exact `029` marker validation**

`mismatches()` uses parameterized `information_schema` queries and returns human-readable messages. Validate these exact markers:

```php
private const REQUIRED_COLUMNS = [
    ['users', 'cultural_preferences', 'text', 'YES', null],
    ['users', 'cultural_preferences_updated_at', 'bigint(20)', 'NO', '0'],
    ['titles', 'original_language', 'varchar(16)', 'YES', null],
    ['titles', 'origin_countries', 'longtext', 'YES', null],
];

private const REQUIRED_INDEXES = [
    ['recommendation_events', 'PRIMARY', 1, 'event_id', 0],
    ['recommendation_events', 'idx_reco_events_user_created', 1, 'user_id', 1],
    ['recommendation_events', 'idx_reco_events_user_created', 2, 'created_at', 1],
    ['recommendation_events', 'idx_reco_events_model_action', 1, 'model_version', 1],
    ['recommendation_events', 'idx_reco_events_model_action', 2, 'action', 1],
    ['recommendation_events', 'idx_reco_events_impression', 1, 'impression_id', 1],
];

private const RECOMMENDATION_EVENT_COLUMNS = [
    ['event_id', 'char(36)', 'NO'],
    ['user_id', 'bigint(20) unsigned', 'NO'],
    ['impression_id', 'char(36)', 'NO'],
    ['movie_id', 'int(11)', 'NO'],
    ['is_tv', 'tinyint(1)', 'NO'],
    ['action', 'varchar(32)', 'NO'],
    ['surface', 'varchar(32)', 'NO'],
    ['source', 'varchar(32)', 'NO'],
    ['model_version', 'varchar(64)', 'NO'],
    ['score_components', 'text', 'YES'],
    ['metadata', 'text', 'YES'],
    ['created_at', 'bigint(20)', 'NO'],
    ['received_at', 'bigint(20)', 'NO'],
];
```

Also require the `recommendation_events` table and `origin_countries` collation `utf8mb4_bin`. Validate `is_tv` default `0`; the remaining `recommendation_events` columns have no explicit default. Normalize MariaDB display-width differences by comparing base type plus unsigned/length where semantically relevant; do not require MySQL-only formatting.

- [ ] **Step 4: Implement ledger creation and empty bootstrap**

`MigrationManager` uses lock name `cinema_plus_schema_migrations`, timeout 10 seconds, and always releases it in `finally`:

```php
private function withLock(callable $operation): mixed
{
    $st = $this->db->prepare('SELECT GET_LOCK(?, 10)');
    $st->execute([self::LOCK_NAME]);
    if ((int) $st->fetchColumn() !== 1) {
        throw new RuntimeException('Could not acquire migration lock.');
    }
    try {
        return $operation();
    } finally {
        $release = $this->db->prepare('SELECT RELEASE_LOCK(?)');
        $release->execute([self::LOCK_NAME]);
    }
}
```

The ledger DDL is:

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(150) NOT NULL PRIMARY KEY,
  checksum CHAR(64) NOT NULL,
  applied_at BIGINT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
```

`bootstrap()` verifies there are no base tables other than `schema_migrations`, executes `database.sql`, creates the ledger if necessary, validates `mismatches()` is empty, and inserts `029_baseline`. If application tables already exist, it throws `Existing schema has no baseline history; run php migrate.php --adopt-baseline=029`.

`run()` checks application-table presence. On an empty database it calls `bootstrap()` and then `migrate()`; otherwise it calls `migrate()` directly. This is the one-command clean-install path used by the CLI.

- [ ] **Step 5: Run bootstrap test, complete suite, and PHPStan**

Run:

```powershell
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationManagerMariaDbTest.php --filter testBootstrapMatchesSnapshotAndRecordsChecksum --no-coverage
composer --working-dir=backend test
composer --working-dir=backend phpstan
```

Expected: bootstrap test passes; all backend tests pass; PHPStan has zero errors.

- [ ] **Step 6: Commit Task 2**

```powershell
git add backend/src/Migrations/BaselineSchemaValidator.php backend/src/Migrations/MigrationManager.php backend/tests/MigrationManagerMariaDbTest.php
git commit -m "feat(database): bootstrap checksum baseline"
```

---

### Task 3: Adoption, Drift Protection, and Forward Execution

**Files:**
- Modify: `backend/src/Migrations/MigrationManager.php`
- Modify: `backend/tests/MigrationManagerMariaDbTest.php`

**Interfaces:**
- Consumes the Task 2 constructor and public methods unchanged.
- Produces stable result: `migrate(): int` returns the count of applied forward migrations.
- Produces stable status keys: `baseline`, `applied`, `pending`, and `drift`.

- [ ] **Step 1: Add failing adoption tests**

Add two tests:

```php
public function testAdoptsAnIntactSnapshotWithoutRunningForwardSql(): void
{
    $this->subject->exec((string) file_get_contents(self::MIGRATIONS . '/database.sql'));
    $this->manager($this->subject)->adoptBaseline();
    self::assertSame('029_baseline', $this->subject->query(
        'SELECT version FROM schema_migrations'
    )->fetchColumn());
}

public function testRejectsAdoptionWhenARequiredMarkerIsMissing(): void
{
    $this->subject->exec((string) file_get_contents(self::MIGRATIONS . '/database.sql'));
    $this->subject->exec('DROP INDEX idx_reco_events_impression ON recommendation_events');
    $this->expectException(RuntimeException::class);
    $this->expectExceptionMessage('recommendation_events.idx_reco_events_impression');
    $this->manager($this->subject)->adoptBaseline();
}
```

Run the two tests and expect RED because adoption is not implemented.

- [ ] **Step 2: Implement explicit adoption**

Under the advisory lock, `adoptBaseline()` rejects an empty database, rejects an existing baseline row, creates/upgrades the ledger, calls `mismatches()`, throws one message containing every mismatch when non-empty, and otherwise inserts only `029_baseline`. It must not call `migrate()`.

Run the adoption tests and expect PASS.

- [ ] **Step 3: Add failing idempotency and checksum-drift tests**

Build each manager with a per-test copied migration directory so tests never mutate repository SQL files:

```php
public function testSecondMigrationRunIsIdempotent(): void
{
    $manager = $this->manager($this->subject);
    $manager->bootstrap();
    self::assertSame(0, $manager->migrate());
    self::assertSame(1, (int) $this->subject->query('SELECT COUNT(*) FROM schema_migrations')->fetchColumn());
}

public function testChecksumDriftStopsBeforePendingMigration(): void
{
    $dir = $this->copiedMigrationDir();
    $manager = $this->manager($this->subject, $dir);
    $manager->bootstrap();
    file_put_contents("$dir/database.sql", "\n-- drift", FILE_APPEND);
    file_put_contents("$dir/030_should_not_run.sql", 'CREATE TABLE should_not_run (id INT PRIMARY KEY);');

    $this->expectException(RuntimeException::class);
    $this->expectExceptionMessage('Checksum drift for 029_baseline');
    try {
        $manager->migrate();
    } finally {
        self::assertFalse($this->tableExists($this->subjectName, 'should_not_run'));
    }
}
```

Run both and expect RED on missing drift validation.

- [ ] **Step 4: Implement ledger validation and status**

Before applying pending files, load all ledger rows, compare the baseline checksum and every still-present applied forward file checksum with `hash_equals()`, and throw `Checksum drift for <version>` on mismatch. `status()` must not acquire a write lock or modify tables; return:

```php
[
    'baseline' => 'applied' | 'missing' | 'drift',
    'applied' => ['030_example.sql'],
    'pending' => ['031_example.sql'],
    'drift' => ['029_baseline'],
]
```

Run the idempotency and drift tests and expect PASS.

- [ ] **Step 5: Add failing forward, stop-on-failure, and lock tests**

Use copied fixtures:

```php
public function testAppliesForwardMigrationExactlyOnce(): void
{
    $dir = $this->copiedMigrationDir();
    file_put_contents("$dir/030_example.sql", 'CREATE TABLE migration_example (id INT PRIMARY KEY);');
    $manager = $this->manager($this->subject, $dir);
    $manager->bootstrap();
    self::assertSame(1, $manager->migrate());
    self::assertSame(0, $manager->migrate());
    self::assertSame(hash_file('sha256', "$dir/030_example.sql"), $this->subject->query(
        "SELECT checksum FROM schema_migrations WHERE version = '030_example.sql'"
    )->fetchColumn());
}

public function testFailureIsNotRecordedAndStopsLaterFiles(): void
{
    $dir = $this->copiedMigrationDir();
    file_put_contents("$dir/030_broken.sql", 'THIS IS NOT SQL;');
    file_put_contents("$dir/031_later.sql", 'CREATE TABLE later_table (id INT PRIMARY KEY);');
    $manager = $this->manager($this->subject, $dir);
    $manager->bootstrap();
    try {
        $manager->migrate();
        self::fail('Expected migration failure.');
    } catch (RuntimeException $e) {
        self::assertStringContainsString('030_broken.sql', $e->getMessage());
        self::assertSame(0, (int) $this->subject->query(
            "SELECT COUNT(*) FROM schema_migrations WHERE version IN ('030_broken.sql','031_later.sql')"
        )->fetchColumn());
        self::assertFalse($this->tableExists($this->subjectName, 'later_table'));
    }
}
```

For locking, hold `GET_LOCK('cinema_plus_schema_migrations', 0)` on a second PDO connection, invoke `migrate()`, assert `Could not acquire migration lock.`, then release the lock in `finally`.

- [ ] **Step 6: Implement forward execution and lock enforcement**

`migrate()` runs entirely inside `withLock()`, validates history before SQL, executes each unrecorded candidate, then inserts its filename/checksum/timestamp. Do not wrap DDL in a misleading transaction. Around each SQL execution, catch `PDOException` and throw `RuntimeException("Migration failed: $filename", 0, $exception)`; this exposes the filename without printing the SQL body, while preserving the database exception as `previous`.

Run the complete MariaDB integration class and expect PASS.

- [ ] **Step 7: Run full backend verification and commit Task 3**

```powershell
composer --working-dir=backend test
composer --working-dir=backend phpstan
git diff --check
git add backend/src/Migrations/MigrationManager.php backend/tests/MigrationManagerMariaDbTest.php
git commit -m "feat(database): enforce safe forward migrations"
```

Expected:  existing and new backend tests pass, PHPStan reports zero errors, and the commit contains only Task 3 files.

---

### Task 4: Thin CLI and Operator Documentation

**Files:**
- Modify: `backend/migrate.php`
- Modify: `backend/README.md`
- Modify: `backend/API_VE_SEMA.md`
- Test: `backend/tests/MigrationManagerMariaDbTest.php`

**Interfaces:**
- Consumes all Task 3 manager interfaces.
- Preserves commands `php migrate.php` and `php migrate.php --status`.
- Adds command `php migrate.php --adopt-baseline=029`.
- CLI exit code is `0` on success and `1` on validation, connection, lock, or SQL failure.

- [ ] **Step 1: Add a failing CLI argument/output test**

Refactor the test harness to generate a temporary `Config.php` returning only the test DB settings and invoke the CLI with `proc_open()` from a copied backend fixture. Assert:

```php
self::assertSame(1, $result->exitCode);
self::assertStringContainsString('Unsupported option: --adopt-baseline=028', $result->stderr);
self::assertStringNotContainsString($password, $result->stderr);
```

Also verify `--status` returns exit `0` and contains `Baseline 029: applied` after bootstrap. Run these tests and expect RED because the old procedural CLI does not expose the new manager behavior.

- [ ] **Step 2: Replace procedural migration logic with the CLI adapter**

The adapter must:

```php
$allowed = ['', '--status', '--adopt-baseline=029'];
$option = $argv[1] ?? '';
if (count($argv) > 2 || !in_array($option, $allowed, true)) {
    fwrite(STDERR, "Unsupported option: " . ($option === '' ? '(none)' : $option) . PHP_EOL);
    exit(1);
}
```

Load Composer autoload, `Config.php`, and `Db::conn($cfg)`. Construct the catalog,
validator, and manager. Dispatch adoption or status explicitly. For the default
command, call `run()`. Print sanitized one-line progress messages through
the manager output callback. Catch `Throwable`, print only `Migration failed:
{$e->getMessage()}` to STDERR, and exit `1`.

- [ ] **Step 3: Run focused CLI and integration tests**

Run the complete `MigrationManagerMariaDbTest.php` with the XAMPP environment variables. Expected: all tests pass and no secret appears in captured output.

- [ ] **Step 4: Update operator documentation**

Change the header comment in `database.sql` from “026 included” to “029 included”; do not alter executable SQL. Document these exact procedures in both backend documents:

```text
Fresh database: php migrate.php
Existing schema without history: back up first, then php migrate.php --adopt-baseline=029
Inspect without writes: php migrate.php --status
Apply future 030+ migrations: back up first, then php migrate.php
```

State that `database.sql` is the authoritative 029 baseline, adoption validates but does not alter application tables, applied SQL files must never be edited, and deployment does not invoke migrations automatically.

- [ ] **Step 5: Run backend verification and commit Task 4**

```powershell
composer --working-dir=backend test
composer --working-dir=backend phpstan
git diff --check
git add backend/migrate.php backend/migrations/database.sql backend/tests/MigrationManagerMariaDbTest.php backend/README.md backend/API_VE_SEMA.md
git commit -m "refactor(database): route migrations through baseline manager"
```

---

### Task 5: MariaDB 10.6 CI Migration Gate

**Files:**
- Modify: `.github/workflows/ci.yml`
- Test: `backend/tests/MigrationManagerMariaDbTest.php`

**Interfaces:**
- Consumes the integration-test environment contract from Task 2.
- Leaves Flutter CI, PHPUnit coverage, and PHPStan commands intact.

- [ ] **Step 1: Change only the database service and health command**

Replace the PHP job service with:

```yaml
services:
  mariadb:
    image: mariadb:10.6
    env:
      MARIADB_ROOT_PASSWORD: cinema_test_root
      MARIADB_DATABASE: cinema_test
    ports:
      - 3306:3306
    options: >-
      --health-cmd="mariadb-admin ping -h 127.0.0.1 -uroot -pcinema_test_root"
      --health-interval=10s
      --health-timeout=5s
      --health-retries=10
```

Rename the schema step to `Validate production schema on MariaDB 10.6`. Keep using the runner's `mysql` client to connect to the MariaDB service; the server engine, not the client binary name, is the compatibility boundary. Do not change PHP or coverage versions.

- [ ] **Step 2: Add the migration integration gate**

Insert after PHPStan and before the production-schema smoke test:

```yaml
- name: Test baseline migration manager on MariaDB 10.6
  env:
    MIGRATION_TEST_HOST: 127.0.0.1
    MIGRATION_TEST_USER: root
    MIGRATION_TEST_PASSWORD: cinema_test_root
    MIGRATION_TEST_DATABASE_PREFIX: cinema_migration_ci
  run: backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationManagerMariaDbTest.php --no-coverage
```

The integration class must create and remove only `cinema_migration_ci_subject`
and `cinema_migration_ci_snapshot` after validating the prefix.

- [ ] **Step 3: Validate workflow syntax and run local equivalents**

Run:

```powershell
$env:MIGRATION_TEST_HOST='127.0.0.1'
$env:MIGRATION_TEST_USER='root'
$env:MIGRATION_TEST_PASSWORD=''
$env:MIGRATION_TEST_DATABASE_PREFIX='cinema_migration_local'
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationManagerMariaDbTest.php --no-coverage
composer --working-dir=backend test
composer --working-dir=backend phpstan
git diff --check
```

Expected: integration tests pass on local MariaDB, the backend suite passes, PHPStan reports zero errors, and whitespace checks are clean. Inspect `.github/workflows/ci.yml` to confirm YAML indentation matches neighboring steps.

- [ ] **Step 4: Commit Task 5**

```powershell
git add .github/workflows/ci.yml
git commit -m "ci(database): test migrations on MariaDB 10.6"
```

---

### Task 6: Final Verification and Review

**Files:**
- Verify all files committed by Tasks 1–5.
- Do not modify `.cpanel.yml`, API request handling, or `backend/src/Config.php`.

**Interfaces:**
- No new interface; this task proves the plan's complete deliverable.

- [ ] **Step 1: Run repository-scope verification**

```powershell
composer --working-dir=backend test
composer --working-dir=backend phpstan
$env:MIGRATION_TEST_HOST='127.0.0.1'
$env:MIGRATION_TEST_USER='root'
$env:MIGRATION_TEST_PASSWORD=''
$env:MIGRATION_TEST_DATABASE_PREFIX='cinema_migration_final'
backend/vendor/bin/phpunit --configuration backend/phpunit.xml backend/tests/MigrationManagerMariaDbTest.php --no-coverage
git diff --check
git status --short
```

Expected: all commands pass; only the pre-existing user-owned `.gitignore` modification and intentionally untracked `graphify-out/` artifacts may remain outside the task commits.

- [ ] **Step 2: Re-run Graphify after source changes**

```powershell
python -m graphify . --update --code-only
python -m graphify cluster-only .
```

Expected: both commands complete; generated `graphify-out/` artifacts remain uncommitted.

- [ ] **Step 3: Request code review**

Review the complete implementation range from the commit before Task 1 through Task 5. Require explicit checks for:

- no heuristic auto-adoption remains;
- no secret-bearing output;
- historical `002–029` SQL is never replayed over the baseline;
- checksum validation occurs before pending SQL;
- MariaDB advisory locks are always released;
- integration tests cannot drop databases outside the validated prefix;
- `.cpanel.yml` and request-time behavior are unchanged.

- [ ] **Step 4: Address only verified findings and re-run affected checks**

For each review finding, reproduce or verify it before editing. Apply the smallest correction, rerun the focused test first, then repeat the full Task 6 Step 1 verification. Commit corrections with a focused Conventional Commit message.
