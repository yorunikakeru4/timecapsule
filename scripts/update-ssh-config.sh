#!/usr/bin/env bash
# Обновить ~/.ssh/config: Host bastion/web/db/app с ProxyJump.
# Публичный адрес bastion меняется после каждой остановки — скрипт переписывает HostName.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"

BASTION_PUB=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
PRIV_BASTION=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
PRIV_APP=$(aws ec2 describe-instances --instance-ids "$APP_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
PRIV_DB=$(aws ec2 describe-instances --instance-ids "$DB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

CONFIG_FILE="$HOME/.ssh/config"
# Идемпотентно: вырезаем старый блок Lab3 между маркерами
if [[ -f "$CONFIG_FILE" ]]; then
  sed -i '/^# BEGIN lab3$/,/^# END lab3$/d' "$CONFIG_FILE"
fi

cat >> "$CONFIG_FILE" <<EOF
# BEGIN lab3
Host bastion
    HostName ${BASTION_PUB}
    User nixos
    IdentityFile ${KEY_FILE}
    IdentitiesOnly yes

Host web
    HostName ${PRIV_APP}
    User nixos
    IdentityFile ${KEY_FILE}
    IdentitiesOnly yes
    ProxyJump bastion

Host app
    HostName ${PRIV_APP}
    User nixos
    IdentityFile ${KEY_FILE}
    IdentitiesOnly yes
    ProxyJump bastion

Host db
    HostName ${PRIV_DB}
    User nixos
    IdentityFile ${KEY_FILE}
    IdentitiesOnly yes
    ProxyJump bastion
# END lab3
EOF
chmod 600 "$CONFIG_FILE"
log "SSH config обновлён: bastion=$BASTION_PUB, web/app=$PRIV_APP, db=$PRIV_DB"
log "Проверка: ssh bastion; ssh app; ssh db"
