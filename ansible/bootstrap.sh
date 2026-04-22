#!/bin/bash
# ansible/bootstrap.sh
#
# Full cluster bootstrap — from Terraform outputs to running RKE2 cluster
#
# Usage:
#   ./bootstrap.sh
#   ./bootstrap.sh --terraform-dir ../terraform
#   ./bootstrap.sh --skip-preflight
#   ./bootstrap.sh --tags rke2-server
#
# Prerequisites:
#   - terraform apply must have been run successfully
#   - SSH key must exist at ~/.ssh/myapp_vms
#   - ansible, terraform, jq must be installed

set -euo pipefail

# ── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}${BOLD}━━━ $1 ━━━${NC}\n"; }
log_success() { echo -e "${GREEN}${BOLD}✓ $1${NC}"; }

# ── Timer ─────────────────────────────────────────────────
start_time=$(date +%s)

elapsed() {
  local end_time
  end_time=$(date +%s)
  echo $(( end_time - start_time ))
}

# ── Defaults ──────────────────────────────────────────────
TERRAFORM_DIR="../terraform"
SSH_KEY="~/.ssh/myapp_vms"
SSH_USER="myapp"
SKIP_PREFLIGHT=false
ANSIBLE_TAGS=""
KUBECONFIG_DEST="~/.kube/myapp-rke2.yaml"

# ── Argument parsing ──────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="$2"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="$2"
      shift 2
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT=true
      shift
      ;;
    --tags)
      ANSIBLE_TAGS="--tags $2"
      shift 2
      ;;
    --help)
      echo "Usage: ./bootstrap.sh [options]"
      echo ""
      echo "Options:"
      echo "  --terraform-dir <path>   Path to terraform directory (default: ../terraform)"
      echo "  --ssh-key <path>         Path to SSH private key (default: ~/.ssh/myapp_vms)"
      echo "  --ssh-user <user>        SSH username (default: myapp)"
      echo "  --skip-preflight         Skip preflight checks"
      echo "  --tags <tags>            Run only specific ansible tags"
      echo "  --help                   Show this help"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      log_error "Run ./bootstrap.sh --help for usage"
      exit 1
      ;;
  esac
done

# ── Banner ────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║     MyApp RKE2 Cluster Bootstrap      ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 1: Prerequisites ─────────────────────────────────
log_step "Step 1/5 — Checking prerequisites"

check_command() {
  local cmd=$1
  local install_hint=$2
  if ! command -v "$cmd" &> /dev/null; then
    log_error "$cmd is not installed. $install_hint"
    exit 1
  fi
  log_info "$cmd found: $(command -v $cmd)"
}

check_command "ansible"   "Install with: pip install ansible"
check_command "terraform" "Install from: https://developer.hashicorp.com/terraform/install"
check_command "jq"        "Install with: apt-get install jq"
check_command "ssh"       "Install with: apt-get install openssh-client"

# Check SSH key exists
SSH_KEY_EXPANDED="${SSH_KEY/\~/$HOME}"
if [ ! -f "$SSH_KEY_EXPANDED" ]; then
  log_error "SSH key not found at $SSH_KEY"
  log_error "Generate one with: ssh-keygen -t ed25519 -f ~/.ssh/myapp_vms"
  exit 1
fi
log_info "SSH key found: $SSH_KEY"

# Check Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
  log_error "Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi
log_info "Terraform directory: $TERRAFORM_DIR"

log_success "All prerequisites met"

# ── Step 2: Generate inventory ────────────────────────────
log_step "Step 2/5 — Generating Ansible inventory from Terraform"

./inventory/generate.sh \
  --terraform-dir "$TERRAFORM_DIR" \
  --ssh-user "$SSH_USER" \
  --ssh-key "$SSH_KEY"

log_success "Inventory generated"

# ── Step 3: Verify SSH connectivity ──────────────────────
log_step "Step 3/5 — Verifying SSH connectivity to all nodes"

log_info "Testing SSH connectivity..."

ansible all -m ping \
  --private-key "$SSH_KEY_EXPANDED" \
  --timeout 30 \
  2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -q "SUCCESS"; then
      log_success "$line"
    elif echo "$line" | grep -q "FAILED\|ERROR\|unreachabl