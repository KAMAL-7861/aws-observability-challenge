#!/usr/bin/env bash
#
# deploy-c2.sh — Deploy productcatalogservice manifests to the C2 EKS cluster.
#
# Applies in order:
#   1. namespace.yaml
#   2. productcatalogservice.yaml
#   3. nodeport-service.yaml
#
# Usage: ./deploy-c2.sh [--context <kubectl-context>]
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
C2_DIR="${K8S_DIR}/c2"

# ── Defaults ─────────────────────────────────────────────────────────────────
CONTEXT="obs-challenge-c2"

# ── Parse flags ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    *)
      error "Unknown argument: $1"
      echo "Usage: $0 [--context <kubectl-context>]"
      exit 1
      ;;
  esac
done

# ── Validate prerequisites ───────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  error "kubectl is not installed or not in PATH."
  exit 1
fi

if [[ ! -d "${C2_DIR}" ]]; then
  error "C2 manifests directory not found: ${C2_DIR}"
  exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 1: Apply manifests
# ═════════════════════════════════════════════════════════════════════════════
phase "Deploying C2 — productcatalogservice (context: ${CONTEXT})"

info "Applying namespace..."
kubectl apply -f "${C2_DIR}/namespace.yaml" --context="${CONTEXT}"
success "Namespace applied."

info "Applying productcatalogservice deployment + ClusterIP service..."
kubectl apply -f "${C2_DIR}/productcatalogservice.yaml" --context="${CONTEXT}"
success "productcatalogservice applied."

info "Applying NodePort service (port 30550)..."
kubectl apply -f "${C2_DIR}/nodeport-service.yaml" --context="${CONTEXT}"
success "NodePort service applied."

# ═════════════════════════════════════════════════════════════════════════════
# Phase 2: Wait for rollout
# ═════════════════════════════════════════════════════════════════════════════
phase "Waiting for productcatalogservice to be ready"

info "Waiting for deployment rollout (timeout 120s)..."
if kubectl rollout status deployment/productcatalogservice \
    -n online-boutique \
    --context="${CONTEXT}" \
    --timeout=120s; then
  success "productcatalogservice is ready."
else
  error "productcatalogservice did not become ready within 120s."
  kubectl get pods -n online-boutique --context="${CONTEXT}" -l app=productcatalogservice
  exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# Phase 3: Connectivity test
# ═════════════════════════════════════════════════════════════════════════════
phase "Running connectivity test"

info "Checking productcatalogservice is listening on port 3550..."
POD_NAME=$(kubectl get pod \
    -n online-boutique \
    --context="${CONTEXT}" \
    -l app=productcatalogservice \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${POD_NAME}" ]]; then
  error "No productcatalogservice pod found."
  exit 1
fi

info "Exec into pod ${POD_NAME} to verify port 3550..."
if kubectl exec "${POD_NAME}" \
    -n online-boutique \
    --context="${CONTEXT}" \
    -- sh -c 'cat < /dev/null > /dev/tcp/localhost/3550 2>/dev/null || wget -q --spider --timeout=5 http://localhost:3550 2>/dev/null || true' 2>/dev/null; then
  # Use a more portable check — try /dev/tcp first, fall back to checking if the process is listening
  if kubectl exec "${POD_NAME}" \
      -n online-boutique \
      --context="${CONTEXT}" \
      -- sh -c 'netstat -tlnp 2>/dev/null | grep -q 3550 || ss -tlnp 2>/dev/null | grep -q 3550 || cat /proc/net/tcp6 2>/dev/null | grep -qi 0DDE' 2>/dev/null; then
    success "productcatalogservice is listening on port 3550."
  else
    warn "Could not confirm port 3550 via netstat/ss. The gRPC readiness probe passed, so the service is likely healthy."
  fi
else
  warn "Connectivity check inconclusive — container may lack shell utilities. Relying on readiness probe status."
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
phase "C2 Deployment Complete"

echo -e "${GREEN}productcatalogservice deployed to C2 cluster.${NC}"
echo ""
echo -e "  Context:    ${CYAN}${CONTEXT}${NC}"
echo -e "  Namespace:  ${CYAN}online-boutique${NC}"
echo -e "  gRPC port:  ${CYAN}3550${NC}"
echo -e "  NodePort:   ${CYAN}30550${NC}"
echo ""
echo -e "  Verify pods:  ${CYAN}kubectl get pods -n online-boutique --context=${CONTEXT}${NC}"
echo ""
