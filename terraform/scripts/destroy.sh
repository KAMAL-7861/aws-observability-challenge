#!/usr/bin/env bash
#
# destroy.sh — Orchestrates Terraform destroy across all environments.
#
# Destroy order (reverse of deploy):
#   1. C1 us-east-1 (PrivateLink consumer + ALB + WAF + EKS + VPC)
#   2. C2 us-west-2 (PrivateLink provider + NLB + EKS + VPC)
#   3. State bootstrap (S3 + DynamoDB) — optional, with confirmation
#
# Usage: ./destroy.sh [--auto-approve]
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

# ── Helper: run terraform destroy in a directory ─────────────────────────────
tf_destroy() {
  local dir="$1"
  shift
  local extra_vars=("$@")

  info "Initializing Terraform in ${dir}..."
  terraform -chdir="${dir}" init -input=false

  local destroy_args=(-input=false)
  if [[ -n "${AUTO_APPROVE}" ]]; then
    destroy_args+=("${AUTO_APPROVE}")
  fi
  for v in "${extra_vars[@]}"; do
    destroy_args+=(-var "${v}")
  done

  info "Destroying Terraform resources in ${dir}..."
  terraform -chdir="${dir}" destroy "${destroy_args[@]}"
}

# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Destroy C1 — us-east-1
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 1/3 — Destroy C1 us-east-1 (PrivateLink Consumer + ALB + WAF + EKS + VPC)"

if [[ ! -d "${C1_DIR}" ]]; then
  warn "C1 environment directory not found: ${C1_DIR} — skipping."
else
  # C1 requires c2_endpoint_service_name variable; try to read it from C2 state,
  # fall back to a dummy value (destroy doesn't need the real value).
  C2_ENDPOINT_SERVICE_NAME=$(terraform -chdir="${C2_DIR}" output -raw endpoint_service_name 2>/dev/null || echo "placeholder-for-destroy")

  tf_destroy "${C1_DIR}" "c2_endpoint_service_name=${C2_ENDPOINT_SERVICE_NAME}"
  success "C1 infrastructure destroyed."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Destroy C2 — us-west-2
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 2/3 — Destroy C2 us-west-2 (PrivateLink Provider + NLB + EKS + VPC)"

if [[ ! -d "${C2_DIR}" ]]; then
  warn "C2 environment directory not found: ${C2_DIR} — skipping."
else
  tf_destroy "${C2_DIR}"
  success "C2 infrastructure destroyed."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Destroy State Bootstrap (optional)
# ═════════════════════════════════════════════════════════════════════════════
phase "Phase 3/3 — Destroy State Bootstrap (S3 + DynamoDB)"

if [[ ! -d "${STATE_BOOTSTRAP_DIR}" ]]; then
  warn "State bootstrap directory not found: ${STATE_BOOTSTRAP_DIR} — skipping."
else
  if [[ -n "${AUTO_APPROVE}" ]]; then
    warn "Auto-approve is set. Destroying state bootstrap resources..."
    tf_destroy "${STATE_BOOTSTRAP_DIR}"
    success "State bootstrap destroyed."
  else
    echo ""
    warn "Destroying the state bootstrap will delete the S3 bucket and DynamoDB lock table."
    warn "This means all Terraform state will be PERMANENTLY LOST."
    echo ""
    read -rp "$(echo -e "${YELLOW}Are you sure you want to destroy the state bootstrap? (yes/no): ${NC}")" confirm
    if [[ "${confirm}" == "yes" ]]; then
      tf_destroy "${STATE_BOOTSTRAP_DIR}"
      success "State bootstrap destroyed."
    else
      info "Skipping state bootstrap destruction."
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
phase "Teardown Complete"

echo -e "${GREEN}All infrastructure has been destroyed.${NC}"
echo ""
