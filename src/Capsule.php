<?php
declare(strict_types=1);

namespace TimeCapsule;

final class Capsule
{
    public static function create(Database $db, int $userId, string $message, string $openAt, ?string $fileName): int
    {
        $st = $db->pdo()->prepare(
            'INSERT INTO capsules (user_id, message, open_at, file_name) VALUES (?, ?, ?, ?) RETURNING id'
        );
        $st->execute([$userId, $message, $openAt, $fileName]);
        return (int)$st->fetchColumn();
    }

    public static function listForUser(Database $db, int $userId): array
    {
        $st = $db->pdo()->prepare(
            'SELECT id, message, open_at, file_name, created_at FROM capsules WHERE user_id = ? ORDER BY created_at DESC'
        );
        $st->execute([$userId]);
        return $st->fetchAll();
    }

    public static function find(Database $db, int $id, int $userId): ?array
    {
        $st = $db->pdo()->prepare(
            'SELECT id, message, open_at, file_name, created_at FROM capsules WHERE id = ? AND user_id = ?'
        );
        $st->execute([$id, $userId]);
        $row = $st->fetch();
        return $row ?: null;
    }
}
