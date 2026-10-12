<?php
declare(strict_types=1);

namespace TimeCapsule;

use PDO;

final class Database
{
    private PDO $pdo;

    public function __construct(array $env)
    {
        $host = $env['DB_HOST'] ?? 'localhost';
        $port = $env['DB_PORT'] ?? '5432';
        $name = $env['DB_NAME'] ?? 'timecapsule';
        $user = $env['DB_USER'] ?? 'timecapsule';
        $pass = $env['DB_PASSWORD'] ?? '';
        $this->pdo = new PDO(
            "pgsql:host={$host};port={$port};dbname={$name}",
            $user,
            $pass,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );
    }

    public function pdo(): PDO
    {
        return $this->pdo;
    }
}
