<?php
declare(strict_types=1);

// Идемпотентная инициализация схемы (deploy.sh шаг 4). Читает .env, создаёт таблицы при отсутствии.
require __DIR__ . '/../src/Env.php';
require __DIR__ . '/../src/Database.php';

use TimeCapsule\Database;
use TimeCapsule\Env;

$env = Env::load(dirname(__DIR__) . '/.env');
try {
    $db = new Database($env);
    $pdo = $db->pdo();
    $pdo->exec(<<<'SQL'
        CREATE TABLE IF NOT EXISTS users (
            id            SERIAL PRIMARY KEY,
            login         TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        CREATE TABLE IF NOT EXISTS capsules (
            id         SERIAL PRIMARY KEY,
            user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            message    TEXT NOT NULL,
            open_at    TIMESTAMP NOT NULL,
            file_name  TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    SQL);
    echo "Database is ready\n";
    exit(0);
} catch (Throwable $e) {
    fwrite(STDERR, "init-db failed: {$e->getMessage()}\n");
    exit(1);
}
