#!/usr/bin/env bash
# Deploy variant B (как в ЛР2): запускается с локальной машины — ssh app ./deploy.sh
# Через bastion работает из-за ProxyJump в ~/.ssh/config.
set -euo pipefail

echo "==> cd /var/www/timecapsule"
cd /var/www/timecapsule

echo "==> git pull --ff-only"
git pull --ff-only

echo "==> composer install (если есть composer.json; иначе пропуск)"
if command -v composer >/dev/null 2>&1 && [[ -f composer.json ]]; then
  composer install --no-dev --optimize-autoloader --no-interaction
else
  echo "    composer не установлен или composer.json отсутствует — пропуск (собственное приложение)"
fi

echo "==> php bin/init-db.php"
php bin/init-db.php

echo "==> sudo systemctl reload php-fpm"
sudo systemctl reload php-fpm || sudo systemctl reload phpfpm-www || true

echo "Готово. На сервере коммит: $(git log -1 --oneline)"
