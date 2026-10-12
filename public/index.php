<?php
declare(strict_types=1);

// TimeCapsule — «письма в будущее». Front controller (nginx: try_files → /index.php).
session_start();

require __DIR__ . '/../src/Env.php';
require __DIR__ . '/../src/Database.php';
require __DIR__ . '/../src/Auth.php';
require __DIR__ . '/../src/Capsule.php';

use TimeCapsule\Auth;
use TimeCapsule\Capsule;
use TimeCapsule\Database;
use TimeCapsule\Env;

$env = Env::load(dirname(__DIR__) . '/.env');
$authEnabled = ($env['AUTH_ENABLED'] ?? 'true') !== 'false';
$db = new Database($env);
$view = static function (string $tpl, array $vars = []) use ($env, $authEnabled): void {
    extract($vars);
    $appUrl = $env['APP_URL'] ?? '';
    require dirname(__DIR__) . "/views/{$tpl}.php";
};

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

// --- /register ---
if ($path === '/register') {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $login = trim($_POST['login'] ?? '');
        $pass = $_POST['password'] ?? '';
        if ($login === '' || strlen($pass) < 4) {
            $error = 'Логин обязателен, пароль — минимум 4 символа';
            $view('register', compact('error'));
            return;
        }
        Auth::register($db, $login, $pass);
        header('Location: /');
        return;
    }
    $view('register');
    return;
}

// --- /login ---
if ($path === '/login') {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (Auth::attempt($db, $_POST['login'] ?? '', $_POST['password'] ?? '')) {
            header('Location: /');
            return;
        }
        $error = 'Неверный логин или пароль';
        $view('login', compact('error'));
        return;
    }
    $view('login');
    return;
}

// --- /logout ---
if ($path === '/logout') {
    Auth::logout();
    header('Location: /');
    return;
}

// --- авторизация ---
$authRequired = $authEnabled && !Auth::check();
if ($authRequired && !in_array($path, ['/', '/login', '/register'], true)) {
    header('Location: /login');
    return;
}
if ($authRequired) {
    $view('login');
    return;
}

$userId = Auth::id();

// --- POST /capsules (создание) ---
if ($path === '/capsules' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $message = trim($_POST['message'] ?? '');
    $openAt = $_POST['open_at'] ?? '';
    $maxMb = (int)($env['MAX_UPLOAD_MB'] ?? '5');
    $uploadDir = dirname(__DIR__) . '/' . ($env['UPLOAD_DIR'] ?? 'storage/uploads');

    if ($message === '' || $openAt === '') {
        $error = 'Сообщение и дата открытия обязательны';
        $view('create', compact('error'));
        return;
    }

    $filePath = null;
    $fileName = null;
    if (!empty($_FILES['attachment']['name']) && $_FILES['attachment']['error'] === UPLOAD_ERR_OK) {
        if ($_FILES['attachment']['size'] > $maxMb * 1024 * 1024) {
            $error = "Файл больше {$maxMb} МБ";
            $view('create', compact('error'));
            return;
        }
        if (!is_dir($uploadDir)) {
            mkdir($uploadDir, 0775, true);
        }
        $fileName = bin2hex(random_bytes(8)) . '_' . basename($_FILES['attachment']['name']);
        $filePath = $uploadDir . '/' . $fileName;
        move_uploaded_file($_FILES['attachment']['tmp_name'], $filePath);
    }

    Capsule::create($db, (int)$userId, $message, $openAt, $fileName);
    header('Location: /');
    return;
}

// --- /capsules/new ---
if ($path === '/capsules/new') {
    $view('create');
    return;
}

// --- /capsules/<id> (открытие капсулы) ---
if (preg_match('#^/capsules/(\d+)$#', $path, $m)) {
    $capsule = Capsule::find($db, (int)$m[1], (int)$userId);
    if (!$capsule) {
        http_response_code(404);
        echo 'Капсула не найдена';
        return;
    }
    $unlocked = strtotime($capsule['open_at']) <= time();
    $fileUrl = $capsule['file_name']
        ? '/download/' . $capsule['id']
        : null;
    $view('open', compact('capsule', 'unlocked', 'fileUrl'));
    return;
}

// --- /download/<id> ---
if (preg_match('#^/download/(\d+)$#', $path, $m)) {
    $capsule = Capsule::find($db, (int)$m[1], (int)$userId);
    $unlocked = $capsule && strtotime($capsule['open_at']) <= time();
    if (!$capsule || !$unlocked || !$capsule['file_name']) {
        http_response_code(403);
        echo 'Капсула ещё закрыта';
        return;
    }
    $uploadDir = dirname(__DIR__) . '/' . ($env['UPLOAD_DIR'] ?? 'storage/uploads');
    $file = $uploadDir . '/' . $capsule['file_name'];
    if (!is_file($file)) {
        http_response_code(404);
        echo 'Файл потерян';
        return;
    }
    header('Content-Type: application/octet-stream');
    header('Content-Disposition: attachment; filename="' . rawurlencode($capsule['file_name']) . '"');
    readfile($file);
    return;
}

// --- главная: список капсул ---
$capsules = $userId !== null ? Capsule::listForUser($db, (int)$userId) : [];
$view('list', compact('capsules', 'authEnabled'));
