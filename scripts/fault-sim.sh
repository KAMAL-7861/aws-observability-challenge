#!/usr/bin/env bash
#
# fault-sim.sh — Simulate a fault by killing productcatalogservice in C2.
#
# This script:
#   1. Kills the productcatalogservice pod in C2
#   2. Monitors pod recovery
#   3. Provides instructions for verifying Elastic alerts
#
# Usage: ./fault-sim.sh [--context <kubectl-context>]
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
phase()   { echo -e "\n${CYAN}══════════════════════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $*${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}\n"; }

CONTEXT="obs-challenge-c2"
NAMESPACE="online-boutique"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="$2"; shift 2 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

phase "Fault Simulation: Kill productcatalogservice in C2"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo -e "  Timestamp:  ${CYAN}${TIMESTAMP}${NC}"
echo -e "  Context:    ${CYAN}${CONTEXT}${NC}"
echo -e "  Namespace:  ${CYAN}${NAMESPACE}${NC}"
echo ""

# Show current pod state
info "Current productcatalogservice pod state:"
kubectl get pods -n "${NAMESPACE}" --context="${CONTEXT}" -l app=productcatalogservice
echo ""

# Kill the pod
info "Deleting productcatalogservice pod..."
kubectl delete pod -l app=productcatalogservice -n "${NAMESPACE}" --context="${CONTEXT}"
success "Pod deleted at ${TIMESTAMP}"

phase "Expected Behavior"

echo -e "  1. ${YELLOW}Pod terminated${NC} — Kubernetes will restart it automatically"
echo -e "  2. ${YELLOW}Frontend errors${NC} — gRPC calls to productcatalogservice will fail"
echo -e "  3. ${YELLOW}Elastic detects${NC} — Pod restart event + error rate spike in logs"
echo -e "  4. ${YELLOW}Alert fires${NC} — Within 5-10 minutes in Kibana Alerts"
echo -e "  5. ${GREEN}Auto-recovery${NC} — Pod restarts, system returns to normal"
echo ""

phase "Monitoring Commands"

echo -e "  Watch pod recovery:"
echo -e "  ${CYAN}kubectl get pods -n ${NAMESPACE} --context=${CONTEXT} -l app=productcatalogservice -w${NC}"
echo ""
echo -e "  Check frontend logs for errors (C1):"
echo -e "  ${CYAN}kubectl logs -n ${NAMESPACE} --context=obs-challenge-c1 -l app=frontend --tail=20${NC}"
echo ""
echo -e "  Verify recovery (wait ~60s, then):"
echo -e "  ${CYAN}kubectl get pods -n ${NAMESPACE} --context=${CONTEXT} -l app=productcatalogservice${NC}"
echo ""

phase "Elastic Verification"

echo -e "  1. Open Kibana → Observability → Alerts"
echo -e "  2. Look for alerts fired after ${CYAN}${TIMESTAMP}${NC}"
echo -e "  3. Expected alerts:"
echo -e "     - ${YELLOW}Pod Restart Alert${NC} for productcatalogservice in C2"
echo -e "     - ${YELLOW}productcatalogservice Unreachable${NC} from frontend in C1"
echo -e "  4. Check dashboard for error rate spike and pod restart count increase"
echo ""

# Wait and show recovery
info "Waiting 30s for pod to restart..."
sleep 30

info "Pod state after recovery:"
kubectl get pods -n "${NAMESPACE}" --context="${CONTEXT}" -l app=productcatalogservice
echo ""
success "Fault simulation complete. Check Elastic for alerts within 5-10 minutes."
