# Baseline Migration Manager Design

## Context

The backend already has `backend/migrate.php`, migrations `002` through `029`,
and a current `backend/migrations/database.sql` snapshot. There is no standalone
`001` base migration. The snapshot already contains the effects of migrations
through `029`, so replaying the numbered files over that snapshot is neither a
valid migration chain nor a safe installation procedure.

Local MariaDB 10.4 diagnostics confirmed that a database built from the current
snapshot has the same normalized table definitions as the previously prepared
comparison database: both contain 23 tables. The failure seen while replaying
`027` was caused by attempting to apply a migration already folded into the
snapshot, not by a difference between those two resulting schemas.

The current migration manager records only a filename and timestamp. On a
database without history, it also infers applied migrations from selected table
and column checks. Those checks cannot prove that the full definitions, indexes,
or constraints match the expected schema.

## Decision

Treat `database.sql` as the authoritative baseline through schema version `029`.
Do not manufacture a historical `001` migration or attempt to reconstruct every
intermediate schema. New incremental migrations start at `030`.

Keep `backend/migrate.php` as the only CLI entry point. Do not add a competing
`backend/scripts/migrate.php`, because existing documentation and operational
instructions already reference the current location.

The production request-time schema-version gate and automatic cPanel deployment
step are explicitly out of scope. They may be designed after the migration
manager and its MariaDB CI coverage are proven.

## Migration Ledger

`schema_migrations` stores:

- `version`: the unique migration identifier, including `029_baseline`;
- `checksum`: the lowercase SHA-256 digest of the source SQL artifact;
- `applied_at`: the application timestamp in milliseconds.

The `029_baseline` checksum is calculated from `database.sql`. Each future
incremental migration stores the checksum of its own SQL file. If the current
checksum of an already recorded artifact differs from its ledger value, the
command fails before applying pending migrations. Applied history is never
silently rewritten.

Migration discovery accepts only filenames with a numeric prefix greater than
`029`, beginning with `030_*.sql`. Duplicate versions, malformed filenames, or a
sequence that moves backwards cause validation failure before any SQL runs.

## Operating Modes

### Empty database bootstrap

When the configured database has no application tables, `php migrate.php`:

1. acquires a database advisory lock;
2. loads `database.sql`;
3. creates or upgrades the migration ledger;
4. records `029_baseline` with the snapshot checksum;
5. applies valid pending `030+` migrations in order;
6. releases the lock.

MariaDB DDL can implicitly commit, so the tool does not promise whole-file or
whole-run rollback. A ledger row is written only after the corresponding SQL
completes successfully.

### Existing database adoption

If application tables exist but no baseline ledger entry exists, ordinary
migration execution stops without changing the schema. The error directs the
operator to the explicit command:

```bash
php migrate.php --adopt-baseline=029
```

Adoption verifies the distinguishing schema markers introduced through `029`,
including the required tables, columns, and indexes for migrations `027`, `028`,
and `029`. If any marker is absent or has an incompatible definition, adoption
fails and lists the mismatches. If validation passes, the tool records only the
`029_baseline` ledger entry and then exits. A separate normal invocation applies
future migrations, keeping adoption auditable and free of bundled schema changes.

### Normal incremental run

With a valid baseline entry, the command validates ledger checksums, acquires the
advisory lock, and applies unrecorded `030+` migrations in numeric order. It stops
on the first failure, does not record the failed migration, and does not attempt
later files. A second run with no new files reports that the database is current
and performs no schema writes.

`--status` remains read-only and reports the baseline, applied migrations,
pending migrations, and checksum drift.

## Error and Security Behavior

The command fails safely when:

- an existing database has no baseline history;
- baseline adoption finds a missing or incompatible schema marker;
- an applied artifact's checksum has changed;
- migration filenames are malformed, duplicated, or out of sequence;
- the advisory lock cannot be acquired;
- a SQL statement fails.

Errors identify the database state or migration filename but never print database
passwords, complete DSNs, configuration secrets, or the full SQL body.

## CI Design

The backend CI database service changes from MySQL 8.4 to MariaDB 10.6 to match
the production database family and version. Existing PHPUnit execution remains
unchanged.

The migration job creates isolated test databases and verifies:

1. **Bootstrap equivalence:** running `php migrate.php` on an empty database
   produces the same normalized schema as directly importing `database.sql`.
2. **Idempotency:** a second run makes no schema or ledger changes.
3. **Checksum drift:** changing a copied, already-applied SQL artifact makes the
   command fail without applying pending migrations.
4. **Adoption rejection:** a snapshot missing a required `029` marker cannot be
   adopted.
5. **Adoption success:** an intact snapshot can be adopted and records the
   expected baseline checksum.
6. **Forward migration:** after bootstrap or adoption, a test-only `030`
   migration is applied exactly once and recorded with its checksum.
7. **Failure stop:** a failing migration is not recorded and prevents subsequent
   migrations from running.

Schema comparison normalizes environment-generated details such as
`AUTO_INCREMENT` counters and dump metadata, while retaining table, column,
index, constraint, engine, charset, and collation definitions.

## Deployment Boundary

This work does not modify `.cpanel.yml` and does not run migrations automatically
during deployment. Automation becomes eligible only after the MariaDB migration
tests are stable and the separate production schema-version gate has been
reviewed. Until then, migration execution remains an explicit CLI operation with
a database backup taken beforehand.

## Success Criteria

- An empty MariaDB 10.6 database reaches the authoritative `029` baseline with
  one command.
- An existing database is never silently classified as current.
- Baseline adoption proves the required schema markers before recording history.
- Applied SQL artifacts are protected by SHA-256 drift detection.
- Only `030+` migrations run incrementally and each runs at most once.
- CI proves bootstrap equivalence, adoption safety, idempotency, drift detection,
  forward progress, and stop-on-failure behavior on MariaDB 10.6.
- Request-time schema gating and deployment automation remain separate follow-up
  changes.
