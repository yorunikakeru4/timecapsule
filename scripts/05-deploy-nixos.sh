#!/usr/bin/env bash
# Задание 13 (для NixOS): декларативный накат конфигурации через nixos-rebuild --flake.
# Для bastion/app интернет есть всегда (public + IGW); для db сначала поднимите NAT (03-nat-up.sh),
# т.к. nixos-rebuild подтягивает postgresql из cache.nixos.org — тот же сценарий, что "установка пакетов"
# в задании 6: временный выход в интернет, затем NAT удаляется.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
require_key
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"

NIXOS_DIR="$(cd "$(dirname "$0")/../nixos" && pwd)"
PUB=$(key_pub)

# Приватные адреса для конфигов (pg_hba подсеть берётся из env; адреса — для отчёта)
PRIV_BASTION=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
PRIV_APP=$(aws ec2 describe-instances --instance-ids "$APP_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
PRIV_DB=$(aws ec2 describe-instances --instance-ids "$DB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

pub_host() { aws ec2 describe-instances --instance-ids "$1" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text; }
BASTION_PUB=$(pub_host "$BASTION_INSTANCE_ID")
[[ "$BASTION_PUB" != "None" && -n "$BASTION_PUB" ]] || die "У bastion нет публичного IP"

# Локальный ssh-шаблон для прогона через bastion
SSH_BASTION="ssh -i $KEY_FILE -o StrictHostKeyChecking=accept-new -o ProxyCommand=none nixos@$BASTION_PUB"
SSH_THROUGH="ssh -i $KEY_FILE -o StrictHostKeyChecking=accept-new -o ProxyJump=nixos@$BASTION_PUB nixos@"

deploy_one() {
  local host="$1" addr="$2" flake_attr="$3"
  log "Копирую nixos-конфиг на $host ($addr, flake=.$flake_attr)"
  # tarball конфига + накат
  tar -C "$NIXOS_DIR" -czf - . | \
    "$SSH_THROUGH$addr" 'rm -rf ~/nixos && mkdir -p ~/nixos && tar -xzf - -C ~/nixos'
  log "nixos-rebuild switch --flake ~/nixos#$flake_attr на $host (первый запуск 5-15 минут)"
  "$SSH_THROUGH$addr" "cd ~/nixos && sudo nixos-rebuild switch --flake .#$flake_attr --accept-flake-config"
}

# user-data уже поднял ssh; дождаться ssh-доступа
wait_ssh() {
  local addr="$1"
  for i in $(seq 1 30); do
    if "$SSH_THROUGH$addr" 'true' 2>/dev/null; then return 0; fi
    sleep 5
  done
  die "SSH к $addr не поднялся за 150 секунд"
}

wait_ssh "$PRIV_BASTION"; deploy_one bastion "$PRIV_BASTION" bastion
wait_ssh "$PRIV_APP";     deploy_one app     "$PRIV_APP"     app
wait_ssh "$PRIV_DB";      deploy_one db      "$PRIV_DB"      db

log "Создаю приложение и БД приложения на db-server (декларативно + init-db)"
"$SSH_THROUGH$PRIV_APP" 'cd /var/www/timecapsule 2>/dev/null && sudo -u nginx php bin/init-db.php || echo "app ещё не задеплоен — запустите app/deploy.sh"'

log "Проверка: ssh nixos@$PRIV_APP 'curl -s localhost/health'"
"$SSH_THROUGH$PRIV_APP" 'curl -s http://127.0.0.1/health' || warn "health ещё не отвечает"
log "Готово. Базовый пароль student/lab3 (задание 6) и app-пользователь (задание 10) создаются nixos-модулем hosts/db.nix"
