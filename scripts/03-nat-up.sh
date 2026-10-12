#!/usr/bin/env bash
# Задание 6 / задание 13 (вариант B): поднять временный NAT Gateway.
# 1. Elastic IP  2. NAT GW в public-a  3. wait available  4. маршрут 0.0.0.0/0 в private-rt  5. сохранить id в .state/nat.env
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"

if [[ -f "$NAT_STATE_FILE" ]] && grep -q 'NAT_GATEWAY_ID=' "$NAT_STATE_FILE"; then
  # shellcheck source=/dev/null
  source "$NAT_STATE_FILE"
  state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_GATEWAY_ID" \
    --query 'NatGateways[0].State' --output text 2>/dev/null || echo deleted)
  if [[ "$state" == "available" || "$state" == "pending" ]]; then
    log "NAT Gateway $NAT_GATEWAY_ID уже существует ($state) — выхожу"
    exit 0
  fi
fi

log "Выделяю Elastic IP под NAT"
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "$(tag_spec elastic-ip "$NAT_EIP_NAME")" \
  --query 'AllocationId' --output text)
EIP_ADDR=$(aws ec2 describe-addresses --allocation-ids "$EIP_ALLOC" \
  --query 'Addresses[0].PublicIp' --output text)

log "Создаю NAT Gateway ${NAT_NAME} в public-a ($PUBLIC_A_SUBNET_ID), EIP $EIP_ADDR"
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_A_SUBNET_ID" \
  --allocation-id "$EIP_ALLOC" \
  --tag-specifications "$(tag_spec nat-gateway "$NAT_NAME")" \
  --query 'NatGatewayId' --output text)

log "Жду состояния available (обычно 2-4 минуты)…"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GATEWAY_ID"

log "Добавляю маршрут 0.0.0.0/0 → NAT в private-rt"
aws ec2 create-route --route-table-id "$PRIVATE_RT_ID" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GATEWAY_ID" >/dev/null

{
  echo "NAT_GATEWAY_ID=$NAT_GATEWAY_ID"
  echo "NAT_EIP_ALLOC=$EIP_ALLOC"
  echo "NAT_EIP_ADDR=$EIP_ADDR"
} > "$NAT_STATE_FILE"

log "Готово: $NAT_GATEWAY_ID (EIP $EIP_ADDR). Файл состояния: $NAT_STATE_FILE"
log "После установки/деплоя обязательно: scripts/04-nat-down.sh"
