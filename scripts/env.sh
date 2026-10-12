#!/usr/bin/env bash
# Общая конфигурация ЛР3. Источник для всех скриптов: source "$(dirname "$0")/env.sh"
set -euo pipefail

# ---- k (порядковый номер в группе) и X = k % 30 ----
K="${K:-3}"
X=$((K % 30))

export AWS_REGION="${AWS_REGION:-eu-central-1}"
export OWNER_NICKNAME="${OWNER_NICKNAME:-croitor.a}"
export PROJECT="timecapsule"
export ENVIRONMENT="dev"
export LAB_TAG="lab3"

# ---- NixOS AMI (официальный, EC2 AMI registry, owner 427812963091) ----
# Последний x86_64 stable на момент подготовки; обновляется скриптом scripts/find-nixos-ami.sh
export NIXOS_AMI_OWNER="427812963091"
export NIXOS_AMI_ID="${NIXOS_AMI_ID:-ami-09d5cc1e26dea7c81}"
export NIXOS_AMI_NAME="nixos/26.05.10620.f5c082a40f75-x86_64-linux"
export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"

# ---- Ключевой пар ----
export KEY_NAME="${KEY_NAME:-croitor.a-kepair}"
export KEY_FILE="${KEY_FILE:-$HOME/.ssh/croitor.a-kepair.pem}"

# ---- Адресное пространство ----
export VPC_CIDR="10.${X}.0.0/16"
export PUBLIC_A_CIDR="10.${X}.0.0/24"
export PUBLIC_B_CIDR="10.${X}.1.0/24"
export PRIVATE_A_CIDR="10.${X}.10.0/24"
export PRIVATE_B_CIDR="10.${X}.11.0/24"
export PUBLIC_A_SUBNET="10.${X}.0.0/24"   # принимаем PostgreSQL только отсюда (pg_hba)

# ---- Зоны доступности ----
export AZ_A="${AWS_REGION}a"
export AZ_B="${AWS_REGION}b"

# ---- Имена ресурсов (правило <project>-<env>-<role>[-<zone>]) ----
export VPC_NAME="${PROJECT}-${ENVIRONMENT}-vpc"
export SUBNET_PUBLIC_A="${PROJECT}-${ENVIRONMENT}-public-a"
export SUBNET_PUBLIC_B="${PROJECT}-${ENVIRONMENT}-public-b"
export SUBNET_PRIVATE_A="${PROJECT}-${ENVIRONMENT}-private-a"
export SUBNET_PRIVATE_B="${PROJECT}-${ENVIRONMENT}-private-b"
export IGW_NAME="${PROJECT}-${ENVIRONMENT}-igw"
export RT_PUBLIC="${PROJECT}-${ENVIRONMENT}-public-rt"
export RT_PRIVATE="${PROJECT}-${ENVIRONMENT}-private-rt"
export SG_BASTION="${PROJECT}-${ENVIRONMENT}-bastion-sg"
export SG_WEB="${PROJECT}-${ENVIRONMENT}-web-sg"
export SG_DB="${PROJECT}-${ENVIRONMENT}-db-sg"
export INSTANCE_BASTION="${PROJECT}-${ENVIRONMENT}-bastion"
export INSTANCE_WEB="${PROJECT}-${ENVIRONMENT}-web"
export INSTANCE_DB="${PROJECT}-${ENVIRONMENT}-db"
export INSTANCE_APP="${PROJECT}-${ENVIRONMENT}-app"
export NAT_NAME="${PROJECT}-${ENVIRONMENT}-nat-a"
export NAT_EIP_NAME="${PROJECT}-${ENVIRONMENT}-nat-a-eip"
export APP_EIP_NAME="${PROJECT}-${ENVIRONMENT}-app-eip"
export AMI_NAME="${PROJECT}-${ENVIRONMENT}-app-lab2"
export DNS_ZONE_NAME="timecapsule.internal"

# ---- State-файлы (создаются скриптами, в .gitignore) ----
export STATE_DIR="${STATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state}"
export NAT_STATE_FILE="${STATE_DIR}/nat.env"
export NET_STATE_FILE="${STATE_DIR}/network.env"
export INSTANCES_STATE_FILE="${STATE_DIR}/instances.env"

# ---- Пароли БД (только для dev-лабы; в отчёт/репозиторий не попадают) ----
export DB_LAB_PASSWORD="${DB_LAB_PASSWORD:-lab3-student-pass}"
export DB_APP_PASSWORD="${DB_APP_PASSWORD:-tc-app-pass-2026}"

# ---- Теги (обязательные по соглашению лабы) ----
tag_spec() {
  local resource_type="$1" name="$2"
  printf 'ResourceType=%s,Tags=[{Key=Name,Value=%s},{Key=Project,Value=%s},{Key=Environment,Value=%s},{Key=Owner,Value=%s},{Key=Lab,Value=%s}]' \
    "$resource_type" "$name" "$PROJECT" "$ENVIRONMENT" "$OWNER_NICKNAME" "$LAB_TAG"
}

# Обычные --tags для API, где нет --tag-specifications
common_tags() {
  echo "Key=Project,Value=${PROJECT} Key=Environment,Value=${ENVIRONMENT} Key=Owner,Value=${OWNER_NICKNAME} Key=Lab,Value=${LAB_TAG}"
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require_aws() {
  command -v aws >/dev/null || die "aws CLI не установлен"
  aws sts get-caller-identity >/dev/null || die "AWS CLI не настроен (нет credentials). Выполните aws configure."
  mkdir -p "$STATE_DIR"
}

require_key() {
  [[ -f "$KEY_FILE" ]] || die "Ключевой файл не найден: $KEY_FILE"
  [[ "$(stat -c '%a' "$KEY_FILE")" == "400" ]] || warn "Рекомендуется chmod 400 $KEY_FILE"
}

# Публичный ключ из .pem — для user-data NixOS
key_pub() {
  ssh-keygen -y -f "$KEY_FILE"
}
