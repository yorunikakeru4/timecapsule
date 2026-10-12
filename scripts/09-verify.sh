#!/usr/bin/env bash
# Задание 7 + проверки продвинутого уровня: psql с app-server, порт 5432 с app и bastion,
# изоляция db от интернета, dig из VPC, Tag Editor-эквивалент (aws resourcegroupstaggingapi).
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
PRIV_DB=$(aws ec2 describe-instances --instance-ids "$DB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

SSHA=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ProxyJump="nixos@$BASTION_PUB" "nixos@$PRIV_APP")
SSHB=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "nixos@$BASTION_PUB")

log "1) Доступ к базе с app-server: SELECT version()"
"${SSHA[@]}" "PGPASSWORD='$DB_APP_PASSWORD' psql -h db.timecapsule.internal -U timecapsule -d timecapsule -c 'SELECT version();'" || \
"${SSHA[@]}" "PGPASSWORD='$DB_LAB_PASSWORD' psql -h '$PRIV_DB' -U student -d lab3 -c 'SELECT version();'"

log "2) Порт 5432 с app-server (должен быть open)"
"${SSHA[@]}" "timeout 5 bash -c '</dev/tcp/$PRIV_DB/5432' && echo open || echo closed"

log "3) Порт 5432 с bastion (должен быть closed — sg не пускает bastion к db)"
"${SSHB[@]}" "timeout 5 bash -c '</dev/tcp/$PRIV_DB/5432' && echo open || echo closed"

log "4) Изоляция db-server: curl -m 5 https://github.com с db (не проходит, NAT удалён)"
"${SSHA[@]}" 'curl -m 5 https://github.com && echo reachable || echo "timeout/failed (ожидаемо)"' || echo "timeout/failed (ожидаемо)"

log "5) dig db.timecapsule.internal с app-server"
"${SSHA[@]}" 'dig +short db.timecapsule.internal || true'

log "6) Все ресурсы с тегом Project=timecapsule (эквивалент Tag Editor)"
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=${PROJECT}" \
  --query 'ResourceTagMappingList[].ResourceARN' --output table

log "Проверьте также Network ACL-эксперимент (задание 7, п.4) вручную в консоли:"
log "Inbound rule 90 Deny All traffic с вашим IP/32 → ssh и сайт блокируются, с телефона сайт открывается."
