#!/usr/bin/env bash
#
# deploy-c1.sh — Deploy Online Boutique manifests to the C1 EKS cluster.
#
# Applies in order:
#   1. namespace.yaml
#   2. external-service.yaml (with VPC endpoint DNS substituted)
#   3. All online-boutique/*.yaml service manifests
#
# Usage: ./deploy-c1.sh --vpc-endpoint-dns <dns-name> [--context <kubectl-context>]
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
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
C1_DIR="${K8S_DIR}/c1"

# ── Defaults ─────────────────────────────────────────────────────────────────
CONTEXT="obs-challenge-c1"
VPC_ENDPOINT_DNS=""

# ── Parse flags ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --vpc-endpoint-dns)
      VPC_ENDPOINT_DNS="$2"
      shift 2
      ;;
    *)
      error "Unknown argument: $1"
      echo "Usage: $0 --vpc-endpoint-dns <dns-name> [--context <kubectl-context>]"
      exit 1
      ;;
  esac
done

# ── Validate required flags ──────────────────────────────────────────────────
if [[ -z "${VPC_ENDPOINT_DNS}" ]]; then
  error "--vpc-endpoint-dns is required."
  echo ""
  echo "Usage: $0 --vpc-endpoint-dns <dns-name> [--context <kubectl-context>]"
  echo ""
  echo "Obtain the VPC Endpoint DNS name by running:"
  echo "  terraform -chdir=terraform/environments/c1-us-east-1 output -raw vpc_endpoint_dns_name"
  exit 1
fi

# ── Validate prerequisites ───────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  error "kubectl is not installed or not in PATH."
  exit 1
fi

if [[ ! -d "${C1_DIR}" ]]; then
  error "C1 manifests directory not found: ${C1_DIR}"
  exit 1
fi

if [[ ! -d "${C1_DIR}/online-boutique" ]]; then
  error "Online Boutique manifests directory not found: ${C1_DIR}/online-boutique"
  exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Apply namespace
# ═════════════════════════════════════════════════════════════════════════════
phase "Deploying C1 — Online Boutique (context: ${CONTEXT})"

info "Applying namespace..."
kubectl apply -f "${C1_DIR}/namespace.yaml" --context="${CONTEXT}"
success "Namespace applied."

# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Apply ExternalName service with VPC endpoint DNS substituted
# ═════════════════════════════════════════════════════════════════════════════
phase "Applying ExternalName service (VPC Endpoint DNS: ${VPC_ENDPOINT_DNS})"

info "Substituting VPC endpoint DNS in external-service.yaml..."
sed "s|<REPLACE_WITH_VPC_ENDPOINT_DNS>|${VPC_ENDPOINT_DNS}|g" \
    "${C1_DIR}/external-service.yaml" | \
    kubectl apply -f - --context="${CONTEXT}"
success "ExternalName service applied with DNS: ${VPC_ENDPOINT_DNS}"

# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Apply all Online Boutique service manifests
# ═════════════════════════════════════════════════════════════════════════════
phase "Applying Online Boutique services"

for manifest in "${C1_DIR}"/online-boutique/*.yaml; do
  svc_name=$(basename "${manifest}" .yaml)
  info "Applying ${svc_name}..."
  kubectl apply -f "${manifest}" --context="${CONTEXT}"
done
success "All Online Boutique services applied."

# ═════════════════════════════════════════════════════════════════════════════
# Phase 4: Wait for frontend rollout
# ═════════════════════════════════════════════════════════════════════════════
phase "Waiting for frontend to be ready"

info "Waiting for frontend deployment rollout (timeout 180s)..."
if kubectl rollout status deployment/frontend \
    -n online-boutique \
    --context="${CONTEXT}" \
    --timeout=180s; then
  success "frontend is ready."
else
  error "frontend did not become ready within 180s."
  kubectl get pods -n online-boutique --context="${CONTEXT}" -l app=frontend
  exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 5: Connectivity test
# ═════════════════════════════════════════════════════════════════════════════
phase "Running connectivity test"

info "Verifying frontend can reach productcatalogservice-external..."
FE_POD=$(kubectl get pod \
    -n online-boutique \
    --context="${CONTEXT}" \
    -l app=frontend \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${FE_POD}" ]]; then
  error "No frontend pod found."
  exit 1
fi

info "Exec into pod ${FE_POD} to resolve productcatalogservice-external..."
if kubectl exec "${FE_POD}" \
    -n online-boutique \
    --context="${CONTEXT}" \
    -- sh -c 'nslookup productcatalogservice-external.online-boutique.svc.cluster.local 2>/dev/null || getent hosts productcatalogservice-external.online-boutique.svc.cluster.local 2>/dev/null' 2>/dev/null; then
  success "productcatalogservice-external DNS resolves successfully."
else
  warn "DNS resolution check inconclusive — container may lack lookup utilities. Verify manually:"
  warn "  kubectl exec ${FE_POD} -n online-boutique --context=${CONTEXT} -- nslookup productcatalogservice-external"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
phase "C1 Deployment Complete"

echo -e "${GREEN}Online Boutique deployed to C1 cluster.${NC}"
echo ""
echo -e "  Context:              ${CYAN}${CONTEXT}${NC}"
echo -e "  Namespace:            ${CYAN}online-boutique${NC}"
echo -e "  VPC Endpoint DNS:     ${CYAN}${VPC_ENDPOINT_DNS}${NC}"
echo -e "  ExternalName target:  ${CYAN}productcatalogservice-external.online-boutique.svc.cluster.local:3550${NC}"
echo ""
echo -e "  Verify pods:  ${CYAN}kubectl get pods -n online-boutique --context=${CONTEXT}${NC}"
echo ""
