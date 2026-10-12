#!/usr/bin/env bash
# Задание 12: перенос данных из локальной (старой) БД на db-server и переключение приложения.
# Старая БД = postgresql на самом app-server (как в ЛР2, localhost) — pg_dump оттуда,
# psql -h db.timecapsule.internal в новую БД, затем DB_HOST в .env и отключение локального postgres.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"

BASTION_PUB=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
PRIV_APP=$(aws ec2 describe-instances --instance-ids "$APP_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

SSHA=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ProxyJump="nixos@$BASTION_PUB" "nixos@$PRIV_APP")

log "1) pg_dump локальной БД app-server → timecapsule.sql"
"${SSHA[@]}" 'cd /var/www/timecapsule && pg_dump -h localhost -U timecapsule -d timecapsule -f /tmp/timecapsule.sql && echo dumped'

log "2) psql в новую БД по db.timecapsule.internal (пароль из DB_APP_PASSWORD)"
"${SSHA[@]}" "PGPASSWORD='$DB_APP_PASSWORD' psql -h db.timecapsule.internal -U timecapsule -d timecapsule -f /tmp/timecapsule.sql && echo restored"

log "3) Переключаю .env: DB_HOST=db.timecapsule.internal + новый пароль, reload php-fpm"
"${SSHA[@]}" "cd /var/www/timecapsule && \
  sed -i 's/^DB_HOST=.*/DB_HOST=db.timecapsule.internal/' .env && \
  sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD=$DB_APP_PASSWORD/' .env && \
  sudo systemctl reload php-fpm"

log "4) Выключаю локальный postgres на app-server (приложение не должно ходить в localhost)"
"${SSHA[@]}" 'sudo systemctl disable --now postgresql || echo "postgresql уже выключен"'

log "5) Проверяю /health и наличие капсул из ЛР2"
"${SSHA[@]}" 'curl -s http://127.0.0.1/health && echo'

log "Готово. Образ timecapsule-dev-app-lab2 в этой версии не создавался:"
log "конфигурация сервера описана декларативно (nixos/flake.nix), поэтому дегистрировать нечего —"
log "AMI из реестра NixOS общая и не тарифицируется."
