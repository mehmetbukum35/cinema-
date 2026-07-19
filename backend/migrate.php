<?php
declare(strict_types=1);

// CLI Check
if (php_sapi_name() !== 'cli') {
    header('HTTP/1.1 403 Forbidden');
    echo "Error: migrate.php must be run via command line interface (CLI).\n";
    exit(1);
}

$SRC = __DIR__ . '/src';
if (!is_dir($SRC)) {
    echo "Error: src directory not found at $SRC\n";
    exit(1);
}

require_once "$SRC/Helpers.php";
require_once "$SRC/Db.php";

$cfgFile = "$SRC/Config.php";
if (!is_file($cfgFile)) {
    echo "Error: Config.php not found at $cfgFile. Please copy Config.sample.php and fill it in.\n";
    exit(1);
}
$cfg = require $cfgFile;

try {
    $db = Db::conn($cfg);
} catch (Throwable $e) {
    echo "Error: Database connection failed: " . $e->getMessage() . "\n";
    exit(1);
}

// 1. Ensure schema_migrations table exists
try {
    $db->exec("CREATE TABLE IF NOT EXISTS `schema_migrations` (
        `version` VARCHAR(150) NOT NULL PRIMARY KEY,
        `applied_at` BIGINT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");
} catch (Throwable $e) {
    echo "Error creating schema_migrations table: " . $e->getMessage() . "\n";
    exit(1);
}

// 2. Helper function to check if table/column exists for auto-detection
$tableExists = function(PDO $db, string $tableName): bool {
    $st = $db->prepare("SHOW TABLES LIKE ?");
    $st->execute([$tableName]);
    return $st->fetchColumn() !== false;
};

$columnExists = function(PDO $db, string $tableName, string $columnName): bool {
    try {
        $st = $db->prepare("SHOW COLUMNS FROM `$tableName` LIKE ?");
        $st->execute([$columnName]);
        return $st->fetchColumn() !== false;
    } catch (Throwable $e) {
        return false;
    }
};

$getColumnType = function(PDO $db, string $tableName, string $columnName): ?string {
    try {
        $st = $db->prepare("SHOW COLUMNS FROM `$tableName` LIKE ?");
        $st->execute([$columnName]);
        $col = $st->fetch(PDO::FETCH_ASSOC);
        return $col ? strtolower($col['Type']) : null;
    } catch (Throwable $e) {
        return null;
    }
};

// 3. Auto-detect existing schema state if schema_migrations is empty and users table exists
$stCount = $db->query("SELECT COUNT(*) FROM schema_migrations");
$migrationCount = (int) $stCount->fetchColumn();

if ($migrationCount === 0 && $tableExists($db, 'users')) {
    echo "Empty migration history detected on an existing database. Auto-detecting schema state...\n";
    $now = now_ms();
    $autoApplied = [];

    // Check Migration 002 (device_tokens table)
    if ($tableExists($db, 'device_tokens')) {
        $autoApplied['002_device_tokens.sql'] = true;
    }
    // Check Migration 003 (recommendations table)
    if ($tableExists($db, 'recommendations')) {
        $autoApplied['003_recommendations.sql'] = true;
    }
    // Check Migration 004 (comment column in ratings)
    if ($columnExists($db, 'ratings', 'comment')) {
        $autoApplied['004_ratings_comment.sql'] = true;
    }
    // Check Migration 005 (rate_limits table)
    if ($tableExists($db, 'rate_limits')) {
        $autoApplied['005_rate_limits.sql'] = true;
    }
    // Check Migration 006 (taste_dna column in users)
    if ($columnExists($db, 'users', 'taste_dna')) {
        $autoApplied['006_taste_dna.sql'] = true;
    }
    // Check Migration 007 (google_sub column in users)
    if ($columnExists($db, 'users', 'google_sub')) {
        $autoApplied['007_google_auth.sql'] = true;
    }
    // Check Migration 008 (google_sub widened to 255 chars)
    if ($columnExists($db, 'users', 'google_sub')) {
        $type = $getColumnType($db, 'users', 'google_sub');
        if ($type !== null && (str_contains($type, '255') || !str_contains($type, '64'))) {
            $autoApplied['008_google_sub_widen.sql'] = true;
        }
    }
    // Check Migration 009 (profile likes)
    if ($tableExists($db, 'profile_likes')) {
        $autoApplied['009_profile_likes.sql'] = true;
    }
    // Check Migration 010 (review moderation schema)
    if ($columnExists($db, 'ratings', 'is_hidden') && $tableExists($db, 'review_reports')) {
        $autoApplied['010_review_moderation.sql'] = true;
    }
    // Check Migration 011 (review ban flag)
    if ($columnExists($db, 'users', 'review_banned')) {
        $autoApplied['011_review_ban.sql'] = true;
    }
    // Check Migration 012 (email verification)
    if ($columnExists($db, 'users', 'email_verified') && $tableExists($db, 'email_verifications')) {
        $autoApplied['012_email_verification.sql'] = true;
    }
    // Check Migration 013 (Apple authentication)
    if ($columnExists($db, 'users', 'apple_sub')) {
        $autoApplied['013_apple_auth.sql'] = true;
    }
    // Check Migration 014 (Couch sessions). Migration 015 is intentionally not
    // auto-marked: re-running its charset conversion is safe and repairs older
    // dumps that created this table with a legacy engine/collation.
    if ($tableExists($db, 'couch_sessions')) {
        $autoApplied['014_couch_sessions.sql'] = true;
    }
    // Check Migration 017 (central title catalog).
    if ($tableExists($db, 'titles')) {
        $autoApplied['017_central_titles.sql'] = true;
    }
    // Check Migration 018 (locale-aware title catalog).
    if ($tableExists($db, 'titles') && $columnExists($db, 'titles', 'locale')) {
        $autoApplied['018_title_locales.sql'] = true;
    }
    // Check Migration 019 (legacy metadata removed from relation tables).
    if (
        $tableExists($db, 'titles')
        && $columnExists($db, 'titles', 'locale')
        && !$columnExists($db, 'ratings', 'title')
        && !$columnExists($db, 'watchlist', 'title')
        && !$columnExists($db, 'favorites', 'title')
    ) {
        $autoApplied['019_drop_legacy_title_metadata.sql'] = true;
    }

    // Insert auto-detected applied migrations
    if (!empty($autoApplied)) {
        $ins = $db->prepare("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)");
        foreach (array_keys($autoApplied) as $ver) {
            $ins->execute([$ver, $now]);
            echo " -> Auto-marked: $ver as already applied.\n";
        }
    }
}

// 4. Scan migrations directory
$migrationsDir = __DIR__ . '/migrations';
if (!is_dir($migrationsDir)) {
    echo "Error: migrations directory not found at $migrationsDir\n";
    exit(1);
}

$files = glob("$migrationsDir/0*.sql");
if ($files === false) {
    echo "Error: Failed to scan migrations directory.\n";
    exit(1);
}

sort($files);

// 5. Parse command line options
$isStatus = in_array('--status', $argv, true);

if ($isStatus) {
    echo "\n=== Migration Status ===\n";
    // Load applied migrations
    $st = $db->query("SELECT version, applied_at FROM schema_migrations ORDER BY version ASC");
    $applied = [];
    while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
        $applied[$row['version']] = (int) $row['applied_at'];
    }

    printf("%-35s | %-20s | %s\n", "Migration Version", "Applied At", "Status");
    echo str_repeat("-", 80) . "\n";

    foreach ($files as $file) {
        $basename = basename($file);
        if (isset($applied[$basename])) {
            $appliedStr = date('Y-m-d H:i:s', (int) ($applied[$basename] / 1000));
            printf("%-35s | %-20s | \033[32mApplied\033[0m\n", $basename, $appliedStr);
        } else {
            printf("%-35s | %-20s | \033[31mPending\033[0m\n", $basename, "N/A");
        }
    }
    echo "\n";
    exit(0);
}

// 6. Run pending migrations
$st = $db->query("SELECT version FROM schema_migrations");
$applied = $st->fetchAll(PDO::FETCH_COLUMN);

$ranCount = 0;
foreach ($files as $file) {
    $basename = basename($file);
    if (in_array($basename, $applied, true)) {
        continue;
    }

    echo "Running migration: $basename...\n";
    $sql = file_get_contents($file);
    if ($sql === false || trim($sql) === '') {
        echo "Warning: Migration file $basename is empty or unreadable. Skipping.\n";
        continue;
    }

    try {
        $db->beginTransaction();
        $db->exec($sql);
        
        $ins = $db->prepare("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)");
        $ins->execute([$basename, now_ms()]);
        
        $db->commit();
        echo " -> Success!\n";
        $ranCount++;
    } catch (Throwable $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        echo " -> Error running migration $basename: " . $e->getMessage() . "\n";
        exit(1);
    }
}

if ($ranCount === 0) {
    echo "Database is up-to-date. No pending migrations.\n";
} else {
    echo "Successfully ran $ranCount migration(s).\n";
}
exit(0);
