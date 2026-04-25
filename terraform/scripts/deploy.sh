#!/usr/bin/env bash
#
# deploy.sh — Orchestrates Terraform deployment across all environments.
#
# Deployment order:
#   1. State bootstrap (S3 + DynamoDB)
#   2. C2 us-west-2 (VPC + EKS + NLB + PrivateLink provider)
#   3. C1 us-east-1 (VPC + EKS + PrivateLink consumer + ALB + WAF)
#
# Usage: ./deploy.sh [--auto-approve]
#

set -euo pipefail

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
phase()   { echo -e "\n${CYAN}══════════════════════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $*${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}\n"; }

# ── Resolve paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_BOOTSTRAP_DIR="${TERRAFORM_DIR}/state-bootstrap"
C2_DIR="${TERRAFORM_DIR}/environments/c2-us-west-2"
C1_DIR="${TERRAFORM_DIR}/environments/c1-us-east-1"

# ── Parse flags ──────────────────────────────────────────────────────────────
AUTO_APPROVE=""
for arg in "$@"; do
  case "$arg" in
    --auto-approve) AUTO_APPROVE="-auto-approve" ;;
    *) error "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Helper: run terraform init + apply in a directory ────────────────────────
tf_deploy() {
  local dir="$1"
  shift
  local extra_vars=("$@")

  info "Initializing Terraform in ${dir}..."
  terraform -chdir="${dir}" init -input=false

  local apply_args=(-input=false)
  if [[ -n "${AUTO_APPROVE}" ]]; then
    apply_args+=("${AUTO_APPROVE}")
  fi
  for v in "${extra_vars[@]}"; do
    apply_args+=(-var "${v}")
  done

  info "Applying Terraform in ${dir}..."
  terraform -chdir="${dir}" apply "${apply_args[@]}"
}

# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: State Bootstrap
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 1/3 — State Bootstrap (S3 + DynamoDB)"

if [[ ! -d "${STATE_BOOTSTRAP_DIR}" ]]; then
  error "State bootstrap directory not found: ${STATE_BOOTSTRAP_DIR}"
  exit 1
fi

tf_deploy "${STATE_BOOTSTRAP_DIR}"
success "State bootstrap complete."

# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: C2 — us-west-2 (VPC + EKS + NLB + PrivateLink provider)
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 2/3 — C2 us-west-2 (VPC + EKS + NLB + PrivateLink Provider)"

if [[ ! -d "${C2_DIR}" ]]; then
  error "C2 environment directory not found: ${C2_DIR}"
  exit 1
fi

tf_deploy "${C2_DIR}"
success "C2 infrastructure deployed."

# Capture the endpoint_service_name output from C2 for C1
info "Extracting endpoint_service_name from C2 outputs..."
C2_ENDPOINT_SERVICE_NAME=$(terraform -chdir="${C2_DIR}" output -raw endpoint_service_name 2>/dev/null)

if [[ -z "${C2_ENDPOINT_SERVICE_NAME}" ]]; then
  error "Failed to retrieve endpoint_service_name from C2. Cannot proceed with C1 deployment."
  exit 1
fi

success "C2 endpoint_service_name: ${C2_ENDPOINT_SERVICE_NAME}"

# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: C1 — us-east-1 (VPC + EKS + PrivateLink consumer + ALB + WAF)
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 3/3 — C1 us-east-1 (VPC + EKS + PrivateLink Consumer + ALB + WAF)"

if [[ ! -d "${C1_DIR}" ]]; then
  error "C1 environment directory not found: ${C1_DIR}"
  exit 1
fi

tf_deploy "${C1_DIR}" "c2_endpoint_service_name=${C2_ENDPOINT_SERVICE_NAME}"
success "C1 infrastructure deployed."

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
phase "Deployment Complete"

ALB_DNS=$(terraform -chdir="${C1_DIR}" output -raw alb_dns_name 2>/dev/null || echo "N/A")
VPCE_DNS=$(terraform -chdir="${C1_DIR}" output -raw vpc_endpoint_dns_name 2>/dev/null || echo "N/A")

echo -e "${GREEN}All infrastructure deployed successfully.${NC}"
echo ""
echo -e "  ALB DNS Name:            ${CYAN}${ALB_DNS}${NC}"
echo -e "  VPC Endpoint DNS Name:   ${CYAN}${VPCE_DNS}${NC}"
echo -e "  C2 Endpoint Service:     ${CYAN}${C2_ENDPOINT_SERVICE_NAME}${NC}"
echo ""
echo -e "  Access the application:  ${CYAN}http://${ALB_DNS}${NC}"
echo ""
