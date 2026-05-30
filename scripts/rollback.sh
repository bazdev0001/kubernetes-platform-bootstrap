#!/usr/bin/env bash
# rollback.sh — Emergency rollback for ArgoCD-managed applications.
#
# Disables ArgoCD auto-sync on the target app, rolls back the underlying
# Helm release (or Deployment) to the previous revision, and verifies health.
#
# Usage:
#   ./scripts/rollback.sh --app <argocd-app-name> [--namespace <ns>] [--revision <n>]
#
# The --revision flag refers to the Helm history revision. Omit it to roll
# back to the immediately previous release (history revision - 1).

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
APP_NAME=""
APP_NAMESPACE=""
TARGET_REVISION=""
DRY_RUN=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
run()     { if [[ "$DRY_RUN" == "true" ]]; then echo -e "${YELLOW}[DRY-RUN]${NC} $*"; else eval "$@"; fi; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Emergency rollback for an ArgoCD-managed application.

Options:
  --app <name>         ArgoCD application name (required)
  --namespace <ns>     Namespace where the app is deployed
  --revision <n>       Helm revision to roll back to (default: previous)
  --dry-run            Print commands without executing
  -h, --help           Show this help message

Examples:
  $(basename "$0") --app kube-prometheus-stack
  $(basename "$0") --app my-service --namespace production --revision 3
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)       APP_NAME="$2";        shift 2 ;;
    --namespace) APP_NAMESPACE="$2";   shift 2 ;;
    --revision)  TARGET_REVISION="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;         shift   ;;
    -h|--help)   usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -z "$APP_NAME" ]] && die "--app is required."

# ---------------------------------------------------------------------------
# Step 1: Confirm intent
# ---------------------------------------------------------------------------
warn "This will roll back ArgoCD app '$APP_NAME'."
warn "Auto-sync will be DISABLED. Re-enable it manually once the rollback is verified."
echo -n "Type the app name to confirm: "
read -r confirm_name
[[ "$confirm_name" == "$APP_NAME" ]] || die "App name mismatch. Aborting."

# ---------------------------------------------------------------------------
# Step 2: Disable ArgoCD auto-sync to prevent it fighting the rollback
# ---------------------------------------------------------------------------
info "Disabling ArgoCD auto-sync for '$APP_NAME'..."
run "argocd app set $APP_NAME --sync-policy none -n $ARGOCD_NAMESPACE"
success "Auto-sync disabled."

# ---------------------------------------------------------------------------
# Step 3: Perform the rollback
# ---------------------------------------------------------------------------
if [[ -n "$TARGET_REVISION" ]]; then
  info "Rolling back '$APP_NAME' to ArgoCD history revision $TARGET_REVISION..."
  run "argocd app rollback $APP_NAME $TARGET_REVISION -n $ARGOCD_NAMESPACE"
else
  info "Rolling back '$APP_NAME' to previous revision..."
  # Get the second-to-last history entry.
  local prev_revision
  prev_revision=$(argocd app history "$APP_NAME" -n "$ARGOCD_NAMESPACE" \
    | tail -2 | head -1 | awk '{print $1}')
  [[ -z "$prev_revision" ]] && die "Could not determine previous revision. Use --revision explicitly."
  info "Previous revision: $prev_revision"
  run "argocd app rollback $APP_NAME $prev_revision -n $ARGOCD_NAMESPACE"
fi

# ---------------------------------------------------------------------------
# Step 4: Wait for the application to reach Healthy state
# ---------------------------------------------------------------------------
info "Waiting for '$APP_NAME' to become Healthy (timeout: 5 minutes)..."
run "argocd app wait $APP_NAME \
  --health \
  --timeout 300 \
  -n $ARGOCD_NAMESPACE"

success "Rollback complete. '$APP_NAME' is Healthy."

# ---------------------------------------------------------------------------
# Step 5: Print reminder
# ---------------------------------------------------------------------------
cat <<EOF

${YELLOW}Important:${NC} Auto-sync is still disabled for '$APP_NAME'.

Once you have:
  1. Verified the rollback is stable
  2. Identified and fixed the root cause in git

Re-enable auto-sync with:
  argocd app set $APP_NAME --sync-policy automated --self-heal --auto-prune

EOF
