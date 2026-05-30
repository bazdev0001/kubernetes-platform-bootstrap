#!/usr/bin/env bash
# bootstrap.sh — Bootstraps ArgoCD and the platform app-of-apps onto a fresh cluster.
#
# Usage:
#   ./scripts/bootstrap.sh --env production [--cloud eks] [--skip-argocd] [--dry-run]
#
# This script is idempotent: running it twice on the same cluster is safe.
# It installs ArgoCD via Helm, waits for it to become healthy, then applies
# the app-of-apps manifest so GitOps takes over from that point forward.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CLOUD="eks"
ENV=""
SKIP_ARGOCD=false
SKIP_MONITORING=false
DRY_RUN=false
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="5.51.4"   # helm chart version for argo-cd
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap ArgoCD and the platform app-of-apps onto a Kubernetes cluster.

Options:
  --env <name>       Environment name matching a tfvars file (required)
  --cloud <provider> Cloud provider: eks | gke | aks (default: eks)
  --skip-argocd      Skip ArgoCD installation (useful if already installed)
  --skip-monitoring  Skip Prometheus stack installation
  --dry-run          Print commands without executing them
  -h, --help         Show this help message

Examples:
  $(basename "$0") --env production
  $(basename "$0") --env staging --cloud gke --skip-monitoring
  $(basename "$0") --env production --dry-run
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)              ENV="$2";          shift 2 ;;
    --cloud)            CLOUD="$2";        shift 2 ;;
    --skip-argocd)      SKIP_ARGOCD=true;  shift   ;;
    --skip-monitoring)  SKIP_MONITORING=true; shift ;;
    --dry-run)          DRY_RUN=true;      shift   ;;
    -h|--help)          usage ;;
    *) die "Unknown option: $1. Run with --help for usage." ;;
  esac
done

[[ -z "$ENV" ]] && die "--env is required."

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
  info "Running preflight checks..."

  local required_tools=(kubectl helm argocd)
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      die "'$tool' is not installed or not on PATH."
    fi
  done

  if ! kubectl cluster-info &>/dev/null; then
    die "kubectl cannot reach the cluster. Check your kubeconfig."
  fi

  local server
  server=$(kubectl config current-context)
  warn "Target cluster context: $server"
  echo -n "Proceed? [y/N] "
  read -r confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."

  success "Preflight checks passed."
}

# ---------------------------------------------------------------------------
# Install ArgoCD
# ---------------------------------------------------------------------------
install_argocd() {
  if [[ "$SKIP_ARGOCD" == "true" ]]; then
    info "Skipping ArgoCD installation (--skip-argocd set)."
    return
  fi

  info "Installing ArgoCD $ARGOCD_VERSION into namespace $ARGOCD_NAMESPACE..."

  run "kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"

  run "helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true"
  run "helm repo update argo"

  local values_file="$REPO_ROOT/helm/argocd/values.yaml"
  local values_flag=""
  [[ -f "$values_file" ]] && values_flag="-f $values_file"

  run "helm upgrade --install argocd argo/argo-cd \
    --namespace $ARGOCD_NAMESPACE \
    --version $ARGOCD_VERSION \
    $values_flag \
    --wait \
    --timeout 5m"

  success "ArgoCD installed."
}

# ---------------------------------------------------------------------------
# Wait for ArgoCD to be ready
# ---------------------------------------------------------------------------
wait_for_argocd() {
  info "Waiting for ArgoCD server to be ready..."

  run "kubectl rollout status deployment/argocd-server \
    -n $ARGOCD_NAMESPACE \
    --timeout=120s"

  success "ArgoCD server is ready."
}

# ---------------------------------------------------------------------------
# Apply the app-of-apps manifest
# ---------------------------------------------------------------------------
apply_app_of_apps() {
  info "Applying app-of-apps manifest..."

  run "kubectl apply -f $REPO_ROOT/manifests/argocd/app-of-apps.yaml"

  success "App-of-apps applied. ArgoCD will now sync all platform applications."
}

# ---------------------------------------------------------------------------
# Print post-bootstrap summary
# ---------------------------------------------------------------------------
print_summary() {
  local argocd_password
  argocd_password=$(kubectl -n "$ARGOCD_NAMESPACE" \
    get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "<not found>")

  cat <<EOF

${GREEN}Bootstrap complete!${NC}

ArgoCD initial admin password: ${YELLOW}${argocd_password}${NC}

Next steps:
  1. Port-forward ArgoCD:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
  2. Login:
       argocd login localhost:8080 --username admin --password '<above>'
  3. Watch sync status:
       argocd app list
  4. Change the admin password immediately:
       argocd account update-password

Platform apps will appear in ArgoCD within a few minutes as they sync.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "================================================================"
  echo "  kubernetes-platform-bootstrap"
  echo "  Environment : $ENV"
  echo "  Cloud       : $CLOUD"
  echo "  Dry-run     : $DRY_RUN"
  echo "================================================================"
  echo ""

  preflight
  install_argocd
  wait_for_argocd
  apply_app_of_apps
  print_summary
}

main "$@"
