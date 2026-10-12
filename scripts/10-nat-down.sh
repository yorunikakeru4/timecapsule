#!/usr/bin/env bash
# Задание 6 (удаление) / задание 13 (вариант B): убрать временный NAT Gateway.
# 1. удалить маршрут  2. удалить NAT GW  3. wait deleted  4. освободить EIP (с ретраями)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"

[[ -f "$NAT_STATE_FILE" ]] || die "Файл состояния NAT не найден ($NAT_STATE_FILE) — возможно, шлюза нет"
# shellcheck source=/dev/null
source "$NAT_STATE_FILE"
[[ -n "${NAT_GATEWAY_ID:-}" ]] || die "NAT_GATEWAY_ID пуст"

log "Удаляю маршрут 0.0.0.0/0 из private-rt (если есть)"
aws ec2 delete-route --route-table-id "$PRIVATE_RT_ID" \
  --destination-cidr-block 0.0.0.0/0 2>/dev/null || warn "маршрута уже нет (Blackhole или удалён)"

log "Удаляю NAT Gateway $NAT_GATEWAY_ID"
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GATEWAY_ID"

log "Жду удаления (может занять несколько минут)…"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_GATEWAY_ID"

# AWS отпускает EIP не сразу после Deleted — ретраи
log "Освобождаю Elastic IP $NAT_EIP_ALLOC (ретраи)"
for i in $(seq 1 12); do
  if aws ec2 release-address --allocation-id "$NAT_EIP_ALLOC" 2>/dev/null; then
    log "EIP освобождён"
    break
  fi
  if [[ "$i" == 12 ]]; then
    die "Не удалось освободить EIP за 12 попыток — проверьте вкладку Elastic IPs вручную"
  fi
  warn "адрес ещё привязан, жду 10 c (попытка $i/12)"
  sleep 10
done

rm -f "$NAT_STATE_FILE"
log "NAT Gateway удалён, маршрут убран, EIP освобождён. В private-rt больше нет выхода в интернет."
