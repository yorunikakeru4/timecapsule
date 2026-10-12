#!/usr/bin/env bash
# Задания 5 и 8: запуск экземпляров на официальном NixOS AMI (EC2 AMI registry, owner 427812963091).
# bastion → public-b, db-server → private-a, app-server → public-a (+ Elastic IP в 07-eip.sh).
# Вместо Amazon Linux 2023 используется NixOS: конфигурация раздаётся user-data (модуль amazon-init)
# и далее накатывается декларативно через nixos-rebuild (scripts/05-deploy-nixos.sh).
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_aws
require_key
# shellcheck source=/dev/null
source "$NET_STATE_FILE"
touch "$INSTANCES_STATE_FILE"

PUB=$(key_pub)
USER_DATA_FILE="$STATE_DIR/userdata-ssh.nix"
# user-data NixOS AMI = выражение NixOS-модуля (amazon-init.nix оценивает его как module)
cat > "$USER_DATA_FILE" <<EOF
{ lib, pkgs, ... }:
{
  users.users.nixos.openssh.authorizedKeys.keys = [ "$PUB" ];
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  # t3.micro без swapfile; логирование в journal
  services.journald.extraConfig = "SystemMaxUse=50M";
}
EOF

launch() {
  local name="$1" subnet="$2" sg="$3" auto_public="$4" state_key="$5"
  local existing
  existing=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$name" "Name=instance-state-name,Values=pending,running" \
    --query 'Reservations[].Instances[].InstanceId' --output text || true)
  if [[ -n "$existing" && "$existing" != "None" ]]; then
    log "$name уже запущен: $existing"
    echo "${state_key}=$existing" >> "$INSTANCES_STATE_FILE"
    return
  fi
  log "Запускаю $name (subnet=$subnet, sg=$sg, auto-assign-public-ip=$auto_public)"
  local id
  id=$(aws ec2 run-instances \
    --image-id "$NIXOS_AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$subnet" \
    --associate-public-ip-address "$auto_public" \
    --security-group-ids "$sg" \
    --user-data "file://$USER_DATA_FILE" \
    --tag-specifications \
      "$(tag_spec instance "$name"),$(tag_spec volume "${name}-root")" \
    --query 'Instances[0].InstanceId' --output text)
  echo "${state_key}=$id" >> "$INSTANCES_STATE_FILE"
  log "$name → $id (ожидание running)"
}

launch "$INSTANCE_BASTION" "$PUBLIC_B_SUBNET_ID" "$BASTION_SG_ID" true  BASTION_INSTANCE_ID
launch "$INSTANCE_DB"      "$PRIVATE_A_SUBNET_ID" "$DB_SG_ID"      false DB_INSTANCE_ID
launch "$INSTANCE_APP"     "$PUBLIC_A_SUBNET_ID"  "$WEB_SG_ID"     true  APP_INSTANCE_ID

log "Жду пока все перейдут в running"
aws ec2 wait instance-running --instance-ids \
  "$(grep -oP '=\K.+' "$INSTANCES_STATE_FILE" | tr '\n' ' ')"

log "Приватные IP (для ~/.ssh/config и pg_hba):"
aws ec2 describe-instances \
  --instance-ids "$(grep -oP '=\K.+' "$INSTANCES_STATE_FILE" | tr '\n' ' ')" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Priv:PrivateIpAddress,Pub:PublicIpAddress}' \
  --output table

log "Дальше: scripts/05-deploy-nixos.sh (для db-server сначала нужен NAT: scripts/03-nat-up.sh)"
