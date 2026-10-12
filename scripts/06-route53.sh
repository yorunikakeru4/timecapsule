#!/usr/bin/env bash
# Задание 11: приватная зона Route 53 timecapsule.internal + A-запись db → приватный IP db-server.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"

PRIV_DB=$(aws ec2 describe-instances --instance-ids "$DB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DNS_ZONE_NAME" \
  --query "HostedZones[?Name=='${DNS_ZONE_NAME}.'].Id" --output text | sed 's|/hostedzone/||')
if [[ -z "$ZONE_ID" || "$ZONE_ID" == "None" ]]; then
  log "Создаю приватную зону $DNS_ZONE_NAME, привязанную к $VPC_ID ($AWS_REGION)"
  ZONE_ID=$(aws route53 create-hosted-zone \
    --name "$DNS_ZONE_NAME" \
    --vpc "VPCRegion=$AWS_REGION,VPCId=$VPC_ID" \
    --caller-reference "lab3-$(date +%s)" \
    --hosted-zone-config "Comment=Private zone for ${PROJECT},PrivateZone=true" \
    --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')
  # обязательные теги (route53 тегирует через tag-resource)
  aws route53 tag-resource --resource-id "$ZONE_ID" \
    --tags "Key=Name,Value=${DNS_ZONE_NAME}" "$(common_tags)"
else
  log "Зона уже есть: $ZONE_ID"
fi

log "Создаю A-запись db.${DNS_ZONE_NAME} → $PRIV_DB (TTL 60)"
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"db.${DNS_ZONE_NAME}\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"${PRIV_DB}\"}]}}]}"

echo "HOSTED_ZONE_ID=$ZONE_ID" >> "$NET_STATE_FILE"
echo "DB_PRIVATE_IP=$PRIV_DB" >> "$NET_STATE_FILE"

log "Проверка с app-server (через bastion) — подождите 1-2 минуты на пропагацию DNS:"
# shellcheck source=/dev/null
source "$INSTANCES_STATE_FILE"
BASTION_PUB=$(aws ec2 describe-instances --instance-ids "$BASTION_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
PRIV_APP=$(aws ec2 describe-instances --instance-ids "$APP_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new \
  -o ProxyJump="nixos@$BASTION_PUB" "nixos@$PRIV_APP" \
  'dig +short db.timecapsule.internal' || true
log "С вашего компьютера имя работать НЕ будет — зона приватная, видна только внутри VPC (это и есть проверка задания 11)."
