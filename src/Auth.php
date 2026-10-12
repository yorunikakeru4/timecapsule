<?php
declare(strict_types=1);

namespace TimeCapsule;

final class Auth
{
    public static function register(Database $db, string $login, string $password): int
    {
        $hash = password_hash($password, PASSWORD_BCRYPT);
        $st = $db->pdo()->prepare('INSERT INTO users (login, password_hash) VALUES (?, ?) RETURNING id');
        $st->execute([$login, $hash]);
        return (int)$st->fetchColumn();
    }

    public static function attempt(Database $db, string $login, string $password): bool
    {
        $st = $db->pdo()->prepare('SELECT id, password_hash FROM users WHERE login = ?');
        $st->execute([$login]);
        $row = $st->fetch();
        if ($row && password_verify($password, $row['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION['uid'] = (int)$row['id'];
            $_SESSION['login'] = $login;
            return true;
        }
        return false;
    }

    public static function check(): bool
    {
        return isset($_SESSION['uid']);
    }

    public static function id(): ?int
    {
        return isset($_SESSION['uid']) ? (int)$_SESSION['uid'] : null;
    }

    public static function loginName(): string
    {
        return $_SESSION['login'] ?? '';
    }

    public static function logout(): void
    {
        unset($_SESSION['uid'], $_SESSION['login']);
        session_regenerate_id(true);
    }
}
