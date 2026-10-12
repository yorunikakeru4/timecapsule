<?php
declare(strict_types=1);

// Изолированный health-check: отвечает даже при сломанном index.php (задание 12).
header('Content-Type: application/json');

function env_line(string $path, string $key): ?string
{
    if (!is_readable($path)) {
        return null;
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        [$k, $v] = array_pad(explode('=', $line, 2), 2, '');
        if (trim($k) === $key) {
            return trim($v);
        }
    }
    return null;
}

$envFile = dirname(__DIR__) . '/.env';
$host = env_line($envFile, 'DB_HOST') ?? 'localhost';
$port = env_line($envFile, 'DB_PORT') ?? '5432';
$name = env_line($envFile, 'DB_NAME') ?? 'timecapsule';
$user = env_line($envFile, 'DB_USER') ?? 'timecapsule';
$pass = env_line($envFile, 'DB_PASSWORD') ?? '';

try {
    $pdo = new PDO(
        "pgsql:host={$host};port={$port};dbname={$name}",
        $user,
        $pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 3]
    );
    $pdo->query('SELECT 1');
    echo json_encode(['status' => 'ok', 'db' => 'ok', 'host' => $host], JSON_UNESCAPED_SLASHES);
} catch (Throwable $e) {
    http_response_code(200);
    echo json_encode(['status' => 'error', 'db' => 'error'], JSON_UNESCAPED_SLASHES);
}
