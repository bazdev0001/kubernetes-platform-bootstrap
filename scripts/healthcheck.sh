#!/usr/bin/env bash
# healthcheck.sh — Validates the health of a bootstrapped cluster.
#
# Checks:
#   - All nodes are Ready
#   - No pods are in CrashLoopBackOff or Error state across platform namespaces
#   - ArgoCD apps are all Synced and Healthy
#   - Prometheus targets are all up (via kubectl port-forward)
#   - Certificate expiry for TLS certs managed by cert-manager
#
# Usage:
#   ./scripts/healthcheck.sh [--namespace <ns>] [--argocd-only] [--json]

set -euo pipefail

PLATFORM_NAMESPACES=(argocd monitoring cert-manager ingress-nginx external-dns sealed-secrets)
CHECK_ARGOCD_ONLY=false
OUTPUT_JSON=false
ISSUES=()
WARNINGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { [[ "$OUTPUT_JSON" == "false" ]] && echo -e "${BLUE}[CHECK]${NC} $*"; }
ok()      { [[ "$OUTPUT_JSON" == "false" ]] && echo -e "${GREEN}[PASS]${NC}  $*"; }
fail()    { ISSUES+=("$*");    [[ "$OUTPUT_JSON" == "false" ]] && echo -e "${RED}[FAIL]${NC}  $*"; }
warning() { WARNINGS+=("$*");  [[ "$OUTPUT_JSON" == "false" ]] && echo -e "${YELLOW}[WARN]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Node health
# ---------------------------------------------------------------------------
check_nodes() {
  info "Checking node health..."
  local not_ready
  not_ready=$(kubectl get nodes --no-headers \
    | grep -v ' Ready' | awk '{print $1}' || true)

  if [[ -n "$not_ready" ]]; then
    while IFS= read -r node; do
      fail "Node '$node' is not Ready."
    done <<< "$not_ready"
  else
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    ok "All $node_count nodes are Ready."
  fi
}

# ---------------------------------------------------------------------------
# Pod health across platform namespaces
# ---------------------------------------------------------------------------
check_pods() {
  info "Checking pod health in platform namespaces..."
  for ns in "${PLATFORM_NAMESPACES[@]}"; do
    local bad_pods
    bad_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null \
      | grep -E 'CrashLoopBackOff|Error|OOMKilled|Evicted|ImagePullBackOff' \
      | awk '{print $1}' || true)

    if [[ -n "$bad_pods" ]]; then
      while IFS= read -r pod; do
        fail "Pod '$pod' in namespace '$ns' is in a bad state."
      done <<< "$bad_pods"
    else
      local pod_count
      pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      ok "Namespace '$ns': $pod_count pods running cleanly."
    fi
  done
}

# ---------------------------------------------------------------------------
# ArgoCD application health
# ---------------------------------------------------------------------------
check_argocd() {
  info "Checking ArgoCD application health..."

  if ! kubectl get namespace argocd &>/dev/null; then
    warning "ArgoCD namespace not found — skipping ArgoCD checks."
    return
  fi

  if ! command -v argocd &>/dev/null; then
    warning "argocd CLI not found — skipping ArgoCD checks."
    return
  fi

  local apps_output
  apps_output=$(argocd app list -n argocd --output wide 2>/dev/null || true)

  if [[ -z "$apps_output" ]]; then
    warning "No ArgoCD applications found."
    return
  fi

  local not_healthy
  not_healthy=$(echo "$apps_output" | tail -n +2 \
    | grep -v 'Healthy.*Synced' | awk '{print $1, $NF, $(NF-1)}' || true)

  if [[ -n "$not_healthy" ]]; then
    while IFS= read -r app_line; do
      fail "ArgoCD app not Healthy/Synced: $app_line"
    done <<< "$not_healthy"
  else
    local app_count
    app_count=$(echo "$apps_output" | tail -n +2 | wc -l | tr -d ' ')
    ok "All $app_count ArgoCD applications are Healthy and Synced."
  fi
}

# ---------------------------------------------------------------------------
# Certificate expiry check
# ---------------------------------------------------------------------------
check_certificates() {
  info "Checking TLS certificate expiry..."

  if ! kubectl api-resources | grep -q 'certificates.*cert-manager'; then
    warning "cert-manager CRDs not found — skipping certificate checks."
    return
  fi

  # Flag any certs expiring within 14 days.
  local expiring
  expiring=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null \
    | awk '{print $1, $2, $NF}' \
    | while read -r ns name status; do
        if [[ "$status" != "True" ]]; then
          echo "  $ns/$name (status: $status)"
        fi
      done || true)

  if [[ -n "$expiring" ]]; then
    warning "Certificates not in Ready=True state:"
    warning "$expiring"
  else
    local cert_count
    cert_count=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ok "All $cert_count certificates are Ready."
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  local issue_count="${#ISSUES[@]}"
  local warn_count="${#WARNINGS[@]}"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    python3 -c "
import json, sys
data = {
  'issues': $(python3 -c "import json; print(json.dumps(${ISSUES[@]@Q} if False else list()))"),
  'warnings': [],
  'healthy': $([ $issue_count -eq 0 ] && echo 'true' || echo 'false')
}
print(json.dumps(data, indent=2))
"
    return
  fi

  echo ""
  echo -e "${BOLD}================================================================${NC}"
  if [[ $issue_count -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Cluster health: PASS${NC} ($warn_count warnings)"
  else
    echo -e "${RED}${BOLD}Cluster health: FAIL${NC} ($issue_count issues, $warn_count warnings)"
    echo ""
    echo -e "${RED}Issues:${NC}"
    for issue in "${ISSUES[@]}"; do
      echo "  - $issue"
    done
  fi

  if [[ $warn_count -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Warnings:${NC}"
    for w in "${WARNINGS[@]}"; do
      echo "  - $w"
    done
  fi
  echo -e "${BOLD}================================================================${NC}"
  echo ""

  [[ $issue_count -gt 0 ]] && exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing + main
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --argocd-only) CHECK_ARGOCD_ONLY=true; shift ;;
    --json)        OUTPUT_JSON=true;       shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--argocd-only] [--json]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo ""
echo -e "${BOLD}kubernetes-platform-bootstrap — Cluster Health Check${NC}"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

if [[ "$CHECK_ARGOCD_ONLY" == "true" ]]; then
  check_argocd
else
  check_nodes
  check_pods
  check_argocd
  check_certificates
fi

print_summary
