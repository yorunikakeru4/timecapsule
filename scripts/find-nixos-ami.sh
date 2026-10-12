#!/usr/bin/env bash
# Вспомогательное: найти свежий официальный NixOS AMI для текущего региона.
# Источник: https://nixos.github.io/amis/ (owner 427812963091, публичные AMI NixOS).
set -euo pipefail
source "$(dirname "$0")/env.sh"

ARCH="${ARCH:-x86_64}"
SERIES="${SERIES:-26.05}"   # текущая stable-серия NixOS на момент подготовки

log "Ищу nixos/${SERIES}*/${ARCH}-linux в $AWS_REGION (owner $NIXOS_AMI_OWNER)"
aws ec2 describe-images --owners "$NIXOS_AMI_OWNER" \
  --filters "Name=name,Values=nixos/${SERIES}*" "Name=architecture,Values=${ARCH}" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].{ImageId:ImageId,Name:Name,Created:CreationDate}' \
  --output table

AMI=$(aws ec2 describe-images --owners "$NIXOS_AMI_OWNER" \
  --filters "Name=name,Values=nixos/${SERIES}*" "Name=architecture,Values=${ARCH}" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "Подставьте в env.sh: export NIXOS_AMI_ID=$AMI"
