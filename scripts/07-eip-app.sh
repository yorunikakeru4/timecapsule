#!/usr/bin/env bash
# Задание 9: Elastic IP для app-server (постоянный адрес, не меняется после stop/start).
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"

log "Выделяю Elastic IP с именем ${APP_EIP_NAME} и обязательными тегами"
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "$(tag_spec elastic-ip "$APP_EIP_NAME")" \
  --query 'AllocationId' --output text)
EIP_ADDR=$(aws ec2 describe-addresses --allocation-ids "$EIP_ALLOC" \
  --query 'Addresses[0].PublicIp' --output text)

log "Привязываю к $INSTANCE_APP ($APP_INSTANCE_ID)"
aws ec2 associate-address --instance-id "$APP_INSTANCE_ID" --allocation-id "$EIP_ALLOC"

{
  echo "APP_EIP_ALLOC=$EIP_ALLOC"
  echo "APP_EIP_ADDR=$EIP_ADDR"
} >> "$INSTANCES_STATE_FILE"

log "Обновите APP_URL в .env приложения на http://$EIP_ADDR и выполните reload php-fpm."
log "Проверка: откройте http://$EIP_ADDR в браузере и войдите пользователем из ЛР2."
