#!/usr/bin/env bash
# Задания 1-3: VPC, подсети, Internet Gateway, таблицы маршрутов, DNS, auto-assign public IP.
# Задание 1 (план адресов) — см. таблицу в README.md отчёта; диапазоны считаются из X в env.sh.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws

log "Создаю VPC ${VPC_NAME} (${VPC_CIDR})"
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(tag_spec vpc "$VPC_NAME")" \
  --query 'Vpc.VpcId' --output text)
echo "VPC_ID=$VPC_ID" > "$NET_STATE_FILE"

log "Включаю DNS resolution и DNS hostnames (нужно для Route 53 приватной зоны)"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

log "Создаю 4 подсети в двух зонах доступности"
PA_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PUBLIC_A_CIDR" \
  --availability-zone "$AZ_A" --tag-specifications "$(tag_spec subnet "$SUBNET_PUBLIC_A")" \
  --query 'Subnet.SubnetId' --output text)
PB_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PUBLIC_B_CIDR" \
  --availability-zone "$AZ_B" --tag-specifications "$(tag_spec subnet "$SUBNET_PUBLIC_B")" \
  --query 'Subnet.SubnetId' --output text)
PRVA_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PRIVATE_A_CIDR" \
  --availability-zone "$AZ_A" --tag-specifications "$(tag_spec subnet "$SUBNET_PRIVATE_A")" \
  --query 'Subnet.SubnetId' --output text)
PRVB_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PRIVATE_B_CIDR" \
  --availability-zone "$AZ_B" --tag-specifications "$(tag_spec subnet "$SUBNET_PRIVATE_B")" \
  --query 'Subnet.SubnetId' --output text)
{
  echo "PUBLIC_A_SUBNET_ID=$PA_ID"
  echo "PUBLIC_B_SUBNET_ID=$PB_ID"
  echo "PRIVATE_A_SUBNET_ID=$PRVA_ID"
  echo "PRIVATE_B_SUBNET_ID=$PRVB_ID"
} >> "$NET_STATE_FILE"

log "Включаю auto-assign public IPv4 в public-a и public-b"
aws ec2 modify-subnet-attribute --subnet-id "$PA_ID" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id "$PB_ID" --map-public-ip-on-launch

log "Создаю и подключаю Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "$(tag_spec internet-gateway "$IGW_NAME")" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
echo "IGW_ID=$IGW_ID" >> "$NET_STATE_FILE"

log "Создаю таблицу маршрутов public-rt с маршрутом 0.0.0.0/0 → IGW"
PUB_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$RT_PUBLIC")" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUB_RT_ID" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$PUB_RT_ID" --subnet-id "$PA_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$PUB_RT_ID" --subnet-id "$PB_ID" >/dev/null
echo "PUBLIC_RT_ID=$PUB_RT_ID" >> "$NET_STATE_FILE"

log "Создаю таблицу маршрутов private-rt (без маршрутов в интернет)"
PRV_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$RT_PRIVATE")" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --route-table-id "$PRV_RT_ID" --subnet-id "$PRVA_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$PRV_RT_ID" --subnet-id "$PRVB_ID" >/dev/null
echo "PRIVATE_RT_ID=$PRV_RT_ID" >> "$NET_STATE_FILE"

log "Готово. Состояние сохранено в $NET_STATE_FILE"
log "Проверка (задание 3):"
aws ec2 describe-route-tables --route-table-ids "$PUB_RT_ID" "$PRV_RT_ID" \
  --query 'RouteTables[].{Name:Tags[?Key==`Name`].Value|[0],Routes:Routes[].{Cidr:DestinationCidrBlock,Target:GatewayId||NatGatewayId}}' \
  --output table
