<?php
declare(strict_types=1);
// PDO bağlantısı (singleton). utf8mb4, hata = exception, prepared statements gerçek.
class Db
{
    private static ?PDO $pdo = null;

    public static function conn(?array $cfg = null): PDO
    {
        if (self::$pdo === null) {
            if ($cfg === null) {
                throw new Exception("Database configuration is required for initialization.");
            }
            $d = $cfg['db'];
            $dsn = "mysql:host={$d['host']};dbname={$d['name']};charset={$d['charset']}";
            self::$pdo = new PDO($dsn, $d['user'], $d['pass'], [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
            ]);
        }
        return self::$pdo;
    }

    /** @internal PHPUnit only */
    public static function inject(PDO $pdo): void
    {
        self::$pdo = $pdo;
    }

    /** @internal PHPUnit only */
    public static function reset(): void
    {
        self::$pdo = null;
    }
}
