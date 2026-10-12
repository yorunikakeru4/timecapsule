#!/usr/bin/env bash
# Завершение работы: остановить экземпляры, убрать NAT (если остался), оставить бесплатную сеть.
# VPC/подсети/SG не удаляются — они бесплатны и нужны в следующих работах.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws

if [[ -f "$NAT_STATE_FILE" ]]; then
  warn "Найден активный NAT — удаляю"
  "$(dirname "$0")/10-nat-down.sh"
fi

if [[ -f "$INSTANCES_STATE_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$INSTANCES_STATE_FILE"
  IDS=""
  for v in BASTION_INSTANCE_ID APP_INSTANCE_ID DB_INSTANCE_ID WEB_INSTANCE_ID; do
    [[ -n "${!v:-}" ]] && IDS="$IDS ${!v}"
  done
  if [[ -n "${IDS// /}" ]]; then
    log "Останавливаю экземпляры:$IDS"
    # shellcheck disable=SC2086
    aws ec2 stop-instances --instance-ids $IDS
  fi
fi

log "Проверяю, что нет Available NAT и лишних EIP"
aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output table || true
aws ec2 describe-addresses \
  --query 'Addresses[?Tags[?Key==`Project`&&Value==`timecapsule`]].{Name:Tags[?Key==`Name`].Value|[0],Ip:PublicIp,Assoc:AssociationId}' \
  --output table

log "Готово. После остановки не платят за compute и публичные IP, но диски и EIP app-server продолжают тарифицироваться."
