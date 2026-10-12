#!/usr/bin/env bash
# Задание 4: Security Groups (bastion-sg, web-sg, db-sg) в нашей VPC.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
# shellcheck source=/dev/null
source "$NET_STATE_FILE"

MY_IP=$(curl -s https://checkip.amazonaws.com)/32
log "Мой внешний IP для bastion-sg: $MY_IP (при смене IP пересоздайте правило)"

# Порядок: bastion-sg → web-sg → db-sg (источник-группа работает только для уже существующей SG)
log "Создаю ${SG_BASTION} (SSH 22 только с моего IP)"
BASTION_SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_BASTION" \
  --description "SSH access to bastion" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec security-group "$SG_BASTION")" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$BASTION_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MY_IP,Description=Admin laptop}]"

log "Создаю ${SG_WEB} (HTTP 80 из интернета; SSH 22 только от bastion-sg)"
WEB_SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_WEB" \
  --description "Web server: HTTP from internet, SSH via bastion" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec security-group "$SG_WEB")" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP}]"
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$BASTION_SG_ID,Description=SSH via bastion}]"

log "Создаю ${SG_DB} (PostgreSQL 5432 только от web-sg; SSH 22 только от bastion-sg)"
DB_SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_DB" \
  --description "PostgreSQL from web/app only, SSH via bastion" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec security-group "$SG_DB")" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$DB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$WEB_SG_ID,Description=PostgreSQL from web/app}]"
aws ec2 authorize-security-group-ingress --group-id "$DB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$BASTION_SG_ID,Description=SSH via bastion}]"

{
  echo "BASTION_SG_ID=$BASTION_SG_ID"
  echo "WEB_SG_ID=$WEB_SG_ID"
  echo "DB_SG_ID=$DB_SG_ID"
} >> "$NET_STATE_FILE"

log "Готово. Проверьте вкладки Inbound rules трёх групп в консоли EC2 → Security Groups."
