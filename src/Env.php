<?php
declare(strict_types=1);

namespace TimeCapsule;

final class Env
{
    public static function load(string $path): array
    {
        $out = [];
        if (!is_readable($path)) {
            return $out;
        }
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#') {
                continue;
            }
            [$k, $v] = array_pad(explode('=', $line, 2), 2, '');
            $out[trim($k)] = trim($v);
        }
        return $out;
    }
}
