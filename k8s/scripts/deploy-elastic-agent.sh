#!/usr/bin/env bash
#
# deploy-elastic-agent.sh — Install Elastic Agent via Helm on both clusters.
#
# Usage:
#   ./deploy-elastic-agent.sh \
#     --fleet-url <FLEET_SERVER_URL> \
#     --enrollment-token <TOKEN> \
#     [--c1-context obs-challenge-c1] \
#     [--c2-context obs-challenge-c2]
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
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
phase()   { echo -e "\n${CYAN}══════════════════════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $*${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}\n"; }

C1_CONTEXT="obs-challenge-c1"
C2_CONTEXT="obs-challenge-c2"
FLEET_URL=""
ENROLLMENT_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fleet-url)         FLEET_URL="$2"; shift 2 ;;
    --enrollment-token)  ENROLLMENT_TOKEN="$2"; shift 2 ;;
    --c1-context)        C1_CONTEXT="$2"; shift 2 ;;
    --c2-context)        C2_CONTEXT="$2"; shift 2 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "${FLEET_URL}" || -z "${ENROLLMENT_TOKEN}" ]]; then
  error "--fleet-url and --enrollment-token are required."
  echo ""
  echo "Usage: $0 --fleet-url <URL> --enrollment-token <TOKEN>"
  echo ""
  echo "Get these from Elastic Cloud:"
  echo "  Fleet URL:         Kibana → Fleet → Settings → Fleet Server hosts"
  echo "  Enrollment Token:  Kibana → Fleet → Enrollment tokens → Create"
  exit 1
fi

# Add Helm repo
phase "Adding Elastic Helm repository"
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo update
success "Helm repo updated."

install_agent() {
  local context="$1"
  local cluster_name="$2"

  phase "Installing Elastic Agent on ${cluster_name} (context: ${context})"

  # Create namespace
  kubectl create namespace elastic-system --context="${context}" 2>/dev/null || true

  # Create secret with enrollment token
  kubectl create secret generic elastic-agent-credentials \
    --from-literal=token="${ENROLLMENT_TOKEN}" \
    -n elastic-system \
    --context="${context}" \
    --dry-run=client -o yaml | kubectl apply -f - --context="${context}"

  # Install or upgrade Elastic Agent via Helm
  helm upgrade --install elastic-agent elastic/elastic-agent \
    --namespace elastic-system \
    --kube-context="${context}" \
    --set agent.fleet.enabled=true \
    --set agent.fleet.url="${FLEET_URL}" \
    --set agent.fleet.token="${ENROLLMENT_TOKEN}" \
    --set agent.fleet.insecure=false \
    --set extraEnvs[0].name=CLUSTER_NAME \
    --set extraEnvs[0].value="${cluster_name}" \
    --wait --timeout 120s

  success "Elastic Agent installed on ${cluster_name}."

  # Verify
  info "Verifying agent pods..."
  kubectl get pods -n elastic-system --context="${context}" -o wide
}

# Install on C1
install_agent "${C1_CONTEXT}" "obs-challenge-c1"

# Install on C2
install_agent "${C2_CONTEXT}" "obs-challenge-c2"

phase "Elastic Agent Deployment Complete"

echo -e "${GREEN}Elastic Agent is running on both clusters.${NC}"
echo ""
echo -e "  Verify in Kibana:  ${CYAN}Fleet → Agents${NC}"
echo -e "  You should see agents from both clusters reporting in."
echo ""
